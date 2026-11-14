#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <winsock2.h>
#include <ws2tcpip.h>
#else
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <sys/socket.h>
#include <unistd.h>
#endif

#include "turbo_input_client.h"

#include <openssl/evp.h>

#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace {

#ifdef _WIN32
using SocketHandle = SOCKET;
constexpr SocketHandle kInvalidSocket = INVALID_SOCKET;
inline void closeSocketHandle(SocketHandle s) {
    if (s != INVALID_SOCKET) {
        closesocket(s);
    }
}
inline int lastSocketError() {
    return WSAGetLastError();
}
inline bool setNonBlocking(SocketHandle s) {
    u_long mode = 1;
    return ioctlsocket(s, FIONBIO, &mode) == 0;
}
#else
using SocketHandle = int;
constexpr SocketHandle kInvalidSocket = -1;
inline void closeSocketHandle(SocketHandle s) {
    if (s >= 0) {
        close(s);
    }
}
inline int lastSocketError() {
    return errno;
}
inline bool setNonBlocking(SocketHandle s) {
    const int flags = fcntl(s, F_GETFL, 0);
    if (flags < 0) return false;
    return fcntl(s, F_SETFL, flags | O_NONBLOCK) == 0;
}
#endif

constexpr size_t kKeyBytes = 32;
constexpr size_t kHeaderBytes = 12;
constexpr size_t kTagBytes = 16;
constexpr size_t kMaxGamepads = 8;
constexpr uint64_t kServerDirectionMask = 0x8000000000000000ULL;
constexpr int64_t kEdgeCarryWindowMs = 20;
constexpr int64_t kPingIntervalMs = 1000;

enum class MsgType : uint8_t {
    ping = 0x01,
    pong = 0x02,
    gamepad_state = 0x10,
    gamepad_motion = 0x11,
    gamepad_arrival = 0x12,
    gamepad_touch = 0x13,
    disconnect_flush = 0x14,
    feedback_rumble = 0x20,
    feedback_rumble_triggers = 0x21,
    feedback_rgb_led = 0x22,
    feedback_adaptive_triggers = 0x23,
    feedback_motion_state = 0x24,
};

struct EvpCtxDeleter {
    void operator()(EVP_CIPHER_CTX *p) const {
        if (p) EVP_CIPHER_CTX_free(p);
    }
};
using EvpCtxPtr = std::unique_ptr<EVP_CIPHER_CTX, EvpCtxDeleter>;

inline uint64_t steadyNowUs() {
    return static_cast<uint64_t>(
        std::chrono::duration_cast<std::chrono::microseconds>(
            std::chrono::steady_clock::now().time_since_epoch())
            .count());
}

inline int64_t steadyNowMs() {
    return static_cast<int64_t>(
        std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::steady_clock::now().time_since_epoch())
            .count());
}

inline void writeU16Le(uint8_t *dst, uint16_t v) {
    dst[0] = static_cast<uint8_t>(v & 0xFFu);
    dst[1] = static_cast<uint8_t>((v >> 8) & 0xFFu);
}

inline void writeU32Le(uint8_t *dst, uint32_t v) {
    dst[0] = static_cast<uint8_t>(v & 0xFFu);
    dst[1] = static_cast<uint8_t>((v >> 8) & 0xFFu);
    dst[2] = static_cast<uint8_t>((v >> 16) & 0xFFu);
    dst[3] = static_cast<uint8_t>((v >> 24) & 0xFFu);
}

inline void writeI16Le(uint8_t *dst, int16_t v) {
    writeU16Le(dst, static_cast<uint16_t>(v));
}

inline void writeU64Le(uint8_t *dst, uint64_t v) {
    for (size_t i = 0; i < 8; ++i) {
        dst[i] = static_cast<uint8_t>((v >> (i * 8)) & 0xFFu);
    }
}

inline void writeF32Le(uint8_t *dst, float f) {
    uint32_t bits = 0;
    std::memcpy(&bits, &f, sizeof(bits));
    writeU32Le(dst, bits);
}

inline uint16_t readU16Le(const uint8_t *src) {
    return static_cast<uint16_t>(src[0]) | (static_cast<uint16_t>(src[1]) << 8);
}

inline uint32_t readU32Le(const uint8_t *src) {
    return static_cast<uint32_t>(src[0]) |
           (static_cast<uint32_t>(src[1]) << 8) |
           (static_cast<uint32_t>(src[2]) << 16) |
           (static_cast<uint32_t>(src[3]) << 24);
}

inline uint64_t readU64Le(const uint8_t *src) {
    uint64_t v = 0;
    for (size_t i = 0; i < 8; ++i) {
        v |= static_cast<uint64_t>(src[i]) << (i * 8);
    }
    return v;
}

bool decodeHexKey(const char *hex, std::array<uint8_t, kKeyBytes> &out) {
    if (!hex) return false;
    const size_t len = std::strlen(hex);
    if (len != kKeyBytes * 2) return false;

    auto nibble = [](char c) -> int {
        if (c >= '0' && c <= '9') return c - '0';
        if (c >= 'a' && c <= 'f') return c - 'a' + 10;
        if (c >= 'A' && c <= 'F') return c - 'A' + 10;
        return -1;
    };

    for (size_t i = 0; i < kKeyBytes; ++i) {
        const int hi = nibble(hex[i * 2]);
        const int lo = nibble(hex[i * 2 + 1]);
        if (hi < 0 || lo < 0) return false;
        out[i] = static_cast<uint8_t>((hi << 4) | lo);
    }
    return true;
}

class ReplayWindow64 {
public:
    bool accept(uint64_t counter) {
        if (!initialized_) {
            initialized_ = true;
            highest_ = counter;
            mask_ = 1ULL;
            return true;
        }
        if (counter > highest_) {
            const uint64_t shift = counter - highest_;
            mask_ = (shift >= 64) ? 1ULL : ((mask_ << shift) | 1ULL);
            highest_ = counter;
            return true;
        }
        const uint64_t age = highest_ - counter;
        if (age >= 64) return false;
        const uint64_t bit = 1ULL << age;
        if ((mask_ & bit) != 0) return false;
        mask_ |= bit;
        return true;
    }

    void reset() {
        initialized_ = false;
        highest_ = 0;
        mask_ = 0;
    }

private:
    bool initialized_ = false;
    uint64_t highest_ = 0;
    uint64_t mask_ = 0;
};

struct PadTxState {
    uint32_t stateSeq = 0;
    uint32_t motionSeq[2] = {0, 0};
    uint32_t touchSeq = 0;
    uint32_t prevButtons = 0;
    uint32_t carriedEdges = 0;
    int64_t carriedEdgesUntilMs = 0;
};

class TurboClientImpl {
public:
    static TurboClientImpl &instance() {
        static TurboClientImpl inst;
        return inst;
    }

    bool start(
        const char *host,
        int udpPort,
        int tcpPort,
        uint32_t sessionId,
        const char *keyHex,
        const TurboFeedbackCallbacks *callbacks) {
        stop();

        if (!host || host[0] == '\0' || sessionId == 0) {
            return false;
        }
        std::array<uint8_t, kKeyBytes> parsedKey {};
        if (!decodeHexKey(keyHex, parsedKey)) {
            return false;
        }

        SocketHandle udpSock = kInvalidSocket;
        if (udpPort > 0) {
            udpSock = connectUdp(host, udpPort);
        }

        SocketHandle tcpSock = kInvalidSocket;
        if (tcpPort > 0) {
            tcpSock = connectLoopbackTcp(tcpPort);
        }

        if (udpSock == kInvalidSocket && tcpSock == kInvalidSocket) {
            return false;
        }

        {
            std::lock_guard<std::mutex> lk(stateMutex_);
            key_ = parsedKey;
            sessionId_.store(sessionId);
            txNonce_.store(1);
            callbacks_ = callbacks ? *callbacks : TurboFeedbackCallbacks{};
            udpSock_ = udpSock;
            tcpSock_ = tcpSock;
            usingTcp_.store(tcpSock != kInvalidSocket);
            pads_.fill({});
            rxReplay_.reset();
            packetsSent_.store(0);
            packetsRecv_.store(0);
            authFailures_.store(0);
            feedbackRecv_.store(0);
            lastRttUs_.store(0);
            active_.store(true);
        }

        // Send initial PING so server binds UDP return endpoint and computes RTT.
        sendPingLockedFree();

        rxStop_.store(false);
        rxThread_ = std::thread(&TurboClientImpl::rxLoop, this);
        return true;
    }

    void stop() {
        const bool wasActive = active_.exchange(false);
        if (wasActive) {
            uint8_t flush[7] = {};
            flush[0] = static_cast<uint8_t>(MsgType::disconnect_flush);
            const uint32_t seq = flushSeq_.fetch_add(1) + 1;
            writeU32Le(flush + 1, seq);
            flush[5] = 0xFFu;
            flush[6] = 0x01u;
            sendPlaintext(flush, sizeof(flush), /*sendDuplicateOnUdp=*/true);
        }

        rxStop_.store(true);
        {
            std::lock_guard<std::mutex> lk(socketMutex_);
            closeSocketHandle(tcpSock_);
            tcpSock_ = kInvalidSocket;
            closeSocketHandle(udpSock_);
            udpSock_ = kInvalidSocket;
        }
        if (rxThread_.joinable()) {
            rxThread_.join();
        }
        usingTcp_.store(false);
        sessionId_.store(0);
    }

    bool isActive() const {
        return active_.load();
    }

    TurboClientStats stats() const {
        TurboClientStats s{};
        s.active = active_.load();
        s.usingTcp = usingTcp_.load();
        s.sessionId = sessionId_.load();
        s.packetsSent = packetsSent_.load();
        s.packetsRecv = packetsRecv_.load();
        s.authFailures = authFailures_.load();
        s.feedbackRecv = feedbackRecv_.load();
        s.lastRttUs = lastRttUs_.load();
        return s;
    }

    bool sendArrival(uint8_t id, uint8_t ctype, uint16_t caps, uint32_t supportedButtons) {
        if (!active_.load() || id >= kMaxGamepads) return false;
        uint32_t seq = 0;
        {
            std::lock_guard<std::mutex> lk(stateMutex_);
            seq = ++pads_[id].stateSeq;
        }
        uint8_t p[13] = {};
        p[0] = static_cast<uint8_t>(MsgType::gamepad_arrival);
        writeU32Le(p + 1, seq);
        p[5] = id;
        p[6] = ctype;
        writeU16Le(p + 7, caps);
        writeU32Le(p + 9, supportedButtons);
        return sendPlaintext(p, sizeof(p), /*sendDuplicateOnUdp=*/true);
    }

    bool sendState(
        uint8_t id,
        uint16_t activeMask,
        uint32_t buttons,
        uint8_t lt,
        uint8_t rt,
        int16_t lx,
        int16_t ly,
        int16_t rx,
        int16_t ry,
        uint8_t flags) {
        if (!active_.load() || id >= kMaxGamepads) return false;

        uint32_t seq = 0;
        uint32_t pressedEdges = 0;
        bool hasNewButtonEdge = false;
        const int64_t nowMs = steadyNowMs();
        {
            std::lock_guard<std::mutex> lk(stateMutex_);
            PadTxState &pad = pads_[id];
            seq = ++pad.stateSeq;
            const uint32_t newlyPressed = buttons & ~pad.prevButtons;
            pad.prevButtons = buttons;

            if (nowMs > pad.carriedEdgesUntilMs) {
                pad.carriedEdges = 0;
            }
            if (newlyPressed != 0) {
                hasNewButtonEdge = true;
                pad.carriedEdges |= newlyPressed;
                pad.carriedEdgesUntilMs = nowMs + kEdgeCarryWindowMs;
            }
            pressedEdges = pad.carriedEdges;
        }

        uint8_t p[27] = {};
        p[0] = static_cast<uint8_t>(MsgType::gamepad_state);
        writeU32Le(p + 1, seq);
        p[5] = id;
        writeU16Le(p + 6, activeMask);
        writeU32Le(p + 8, buttons);
        p[12] = lt;
        p[13] = rt;
        writeI16Le(p + 14, lx);
        writeI16Le(p + 16, ly);
        writeI16Le(p + 18, rx);
        writeI16Le(p + 20, ry);
        writeU32Le(p + 22, pressedEdges);
        p[26] = flags;
        return sendPlaintext(p, sizeof(p), /*sendDuplicateOnUdp=*/hasNewButtonEdge);
    }

    bool sendMotion(uint8_t id, uint8_t motionType, float x, float y, float z) {
        if (!active_.load() || id >= kMaxGamepads) return false;
        if (motionType != 0x01 && motionType != 0x02) return false;
        uint32_t seq = 0;
        {
            std::lock_guard<std::mutex> lk(stateMutex_);
            seq = ++pads_[id].motionSeq[motionType == 0x01 ? 0 : 1];
        }
        uint8_t p[19] = {};
        p[0] = static_cast<uint8_t>(MsgType::gamepad_motion);
        writeU32Le(p + 1, seq);
        p[5] = id;
        p[6] = motionType;
        writeF32Le(p + 7, x);
        writeF32Le(p + 11, y);
        writeF32Le(p + 15, z);
        return sendPlaintext(p, sizeof(p), /*sendDuplicateOnUdp=*/false);
    }

    bool sendTouch(uint8_t id, uint8_t eventType, uint32_t pointerId, float x, float y, float pressure) {
        if (!active_.load() || id >= kMaxGamepads) return false;
        uint32_t seq = 0;
        {
            std::lock_guard<std::mutex> lk(stateMutex_);
            seq = ++pads_[id].touchSeq;
        }
        uint8_t p[23] = {};
        p[0] = static_cast<uint8_t>(MsgType::gamepad_touch);
        writeU32Le(p + 1, seq);
        p[5] = id;
        p[6] = eventType;
        writeU32Le(p + 7, pointerId);
        writeF32Le(p + 11, x);
        writeF32Le(p + 15, y);
        writeF32Le(p + 19, pressure);
        return sendPlaintext(p, sizeof(p), /*sendDuplicateOnUdp=*/eventType != 0x03);
    }

private:
    TurboClientImpl() = default;
    ~TurboClientImpl() {
        stop();
    }

    static SocketHandle connectUdp(const char *host, int port) {
        struct addrinfo hints {};
        hints.ai_family = AF_UNSPEC;
        hints.ai_socktype = SOCK_DGRAM;
        hints.ai_protocol = IPPROTO_UDP;

        struct addrinfo *res = nullptr;
        const std::string portStr = std::to_string(port);
        if (getaddrinfo(host, portStr.c_str(), &hints, &res) != 0 || !res) {
            return kInvalidSocket;
        }

        SocketHandle chosen = kInvalidSocket;
        for (struct addrinfo *p = res; p != nullptr; p = p->ai_next) {
            SocketHandle s = socket(p->ai_family, p->ai_socktype, p->ai_protocol);
            if (s == kInvalidSocket) continue;
            if (connect(s, p->ai_addr, static_cast<socklen_t>(p->ai_addrlen)) == 0) {
                setNonBlocking(s);
                chosen = s;
                break;
            }
            closeSocketHandle(s);
        }
        freeaddrinfo(res);
        return chosen;
    }

    static SocketHandle connectLoopbackTcp(int port) {
        SocketHandle s = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
        if (s == kInvalidSocket) return kInvalidSocket;

        setNonBlocking(s);
        int one = 1;
        setsockopt(s, IPPROTO_TCP, TCP_NODELAY, reinterpret_cast<const char *>(&one), sizeof(one));

        struct sockaddr_in addr {};
        addr.sin_family = AF_INET;
        addr.sin_port = htons(static_cast<uint16_t>(port));
        addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

        int rc = connect(s, reinterpret_cast<const struct sockaddr *>(&addr), sizeof(addr));
        if (rc == 0) {
            return s;
        }

#ifdef _WIN32
        const int err = WSAGetLastError();
        if (err != WSAEWOULDBLOCK) {
            closeSocketHandle(s);
            return kInvalidSocket;
        }
        fd_set wfds;
        FD_ZERO(&wfds);
        FD_SET(s, &wfds);
        timeval tv{0, 120000};
        if (select(0, nullptr, &wfds, nullptr, &tv) <= 0) {
            closeSocketHandle(s);
            return kInvalidSocket;
        }
#else
        if (errno != EINPROGRESS) {
            closeSocketHandle(s);
            return kInvalidSocket;
        }
        struct pollfd pfd {};
        pfd.fd = s;
        pfd.events = POLLOUT;
        if (poll(&pfd, 1, 120) <= 0) {
            closeSocketHandle(s);
            return kInvalidSocket;
        }
#endif
        int soErr = 0;
        socklen_t len = sizeof(soErr);
        if (getsockopt(s, SOL_SOCKET, SO_ERROR, reinterpret_cast<char *>(&soErr), &len) != 0 || soErr != 0) {
            closeSocketHandle(s);
            return kInvalidSocket;
        }
        return s;
    }

    bool sealPacket(const uint8_t *plain, size_t plainLen, std::vector<uint8_t> &outWire) {
        const uint32_t sid = sessionId_.load();
        if (sid == 0 || plainLen == 0) return false;
        const uint64_t nonce = txNonce_.fetch_add(1) & 0x7FFFFFFFFFFFFFFFULL;

        outWire.resize(kHeaderBytes + plainLen + kTagBytes);
        writeU32Le(outWire.data(), sid);
        writeU64Le(outWire.data() + 4, nonce);

        EvpCtxPtr ctx(EVP_CIPHER_CTX_new());
        if (!ctx) return false;
        if (EVP_EncryptInit_ex(ctx.get(), EVP_chacha20_poly1305(), nullptr, nullptr, nullptr) != 1) return false;
        if (EVP_CIPHER_CTX_ctrl(ctx.get(), EVP_CTRL_AEAD_SET_IVLEN, static_cast<int>(kHeaderBytes), nullptr) != 1) return false;
        if (EVP_EncryptInit_ex(ctx.get(), nullptr, nullptr, key_.data(), outWire.data()) != 1) return false;

        int outLen = 0;
        if (EVP_EncryptUpdate(ctx.get(), nullptr, &outLen, outWire.data(), static_cast<int>(kHeaderBytes)) != 1) return false;
        if (EVP_EncryptUpdate(
                ctx.get(),
                outWire.data() + kHeaderBytes,
                &outLen,
                plain,
                static_cast<int>(plainLen)) != 1) {
            return false;
        }
        int finLen = 0;
        if (EVP_EncryptFinal_ex(ctx.get(), outWire.data() + kHeaderBytes + outLen, &finLen) != 1) return false;
        if (EVP_CIPHER_CTX_ctrl(
                ctx.get(),
                EVP_CTRL_AEAD_GET_TAG,
                static_cast<int>(kTagBytes),
                outWire.data() + kHeaderBytes + outLen + finLen) != 1) {
            return false;
        }
        outWire.resize(kHeaderBytes + static_cast<size_t>(outLen + finLen) + kTagBytes);
        return true;
    }

    bool openPacket(const uint8_t *wire, size_t wireLen, std::vector<uint8_t> &outPlain) {
        if (!wire || wireLen < kHeaderBytes + 1 + kTagBytes) return false;
        const uint32_t sid = readU32Le(wire);
        const uint64_t nonce = readU64Le(wire + 4);
        if (sid != sessionId_.load() || (nonce & kServerDirectionMask) == 0) {
            return false;
        }
        const uint64_t counter = nonce & ~kServerDirectionMask;

        const size_t cipherLen = wireLen - kHeaderBytes - kTagBytes;
        const uint8_t *ciphertext = wire + kHeaderBytes;
        const uint8_t *tag = wire + kHeaderBytes + cipherLen;

        EvpCtxPtr ctx(EVP_CIPHER_CTX_new());
        if (!ctx) return false;
        if (EVP_DecryptInit_ex(ctx.get(), EVP_chacha20_poly1305(), nullptr, nullptr, nullptr) != 1) return false;
        if (EVP_CIPHER_CTX_ctrl(ctx.get(), EVP_CTRL_AEAD_SET_IVLEN, static_cast<int>(kHeaderBytes), nullptr) != 1) return false;
        if (EVP_DecryptInit_ex(ctx.get(), nullptr, nullptr, key_.data(), wire) != 1) return false;

        int outLen = 0;
        if (EVP_DecryptUpdate(ctx.get(), nullptr, &outLen, wire, static_cast<int>(kHeaderBytes)) != 1) return false;
        outPlain.resize(cipherLen);
        if (EVP_DecryptUpdate(ctx.get(), outPlain.data(), &outLen, ciphertext, static_cast<int>(cipherLen)) != 1) {
            return false;
        }
        if (EVP_CIPHER_CTX_ctrl(
                ctx.get(),
                EVP_CTRL_AEAD_SET_TAG,
                static_cast<int>(kTagBytes),
                const_cast<uint8_t *>(tag)) != 1) {
            return false;
        }
        int finLen = 0;
        if (EVP_DecryptFinal_ex(ctx.get(), outPlain.data() + outLen, &finLen) != 1) {
            authFailures_.fetch_add(1);
            return false;
        }
        outPlain.resize(static_cast<size_t>(outLen + finLen));

        if (!rxReplay_.accept(counter)) {
            return false;
        }
        return true;
    }

    static bool writeAllBlocking(SocketHandle s, const uint8_t *data, size_t len) {
        size_t sent = 0;
        while (sent < len) {
            const int n = static_cast<int>(
                send(s, reinterpret_cast<const char *>(data + sent), static_cast<int>(len - sent), 0));
            if (n > 0) {
                sent += static_cast<size_t>(n);
                continue;
            }
            const int err = lastSocketError();
#ifdef _WIN32
            if (err == WSAEWOULDBLOCK) {
                std::this_thread::sleep_for(std::chrono::microseconds(200));
                continue;
            }
#else
            if (err == EINTR || err == EAGAIN || err == EWOULDBLOCK) {
                std::this_thread::sleep_for(std::chrono::microseconds(200));
                continue;
            }
#endif
            return false;
        }
        return true;
    }

    bool sendPlaintext(const uint8_t *plain, size_t plainLen, bool sendDuplicateOnUdp) {
        std::vector<uint8_t> wire;
        if (!sealPacket(plain, plainLen, wire)) return false;

        std::lock_guard<std::mutex> lk(socketMutex_);
        if (usingTcp_.load() && tcpSock_ != kInvalidSocket) {
            std::vector<uint8_t> framed(2 + wire.size());
            writeU16Le(framed.data(), static_cast<uint16_t>(wire.size()));
            std::memcpy(framed.data() + 2, wire.data(), wire.size());
            if (writeAllBlocking(tcpSock_, framed.data(), framed.size())) {
                packetsSent_.fetch_add(1);
                return true;
            }
            // Fall back to UDP seamlessly if loopback TCP drops.
            closeSocketHandle(tcpSock_);
            tcpSock_ = kInvalidSocket;
            usingTcp_.store(false);
        }

        if (udpSock_ == kInvalidSocket) return false;
        const int sent1 = static_cast<int>(
            send(udpSock_, reinterpret_cast<const char *>(wire.data()), static_cast<int>(wire.size()), 0));
        if (sent1 <= 0) return false;
        packetsSent_.fetch_add(1);

        if (sendDuplicateOnUdp) {
            std::vector<uint8_t> dupWire;
            if (sealPacket(plain, plainLen, dupWire)) {
                const int sent2 = static_cast<int>(send(
                    udpSock_, reinterpret_cast<const char *>(dupWire.data()), static_cast<int>(dupWire.size()), 0));
                if (sent2 > 0) {
                    packetsSent_.fetch_add(1);
                }
            }
        }
        return true;
    }

    void sendPingLockedFree() {
        uint8_t p[9] = {};
        p[0] = static_cast<uint8_t>(MsgType::ping);
        writeU64Le(p + 1, steadyNowUs());
        sendPlaintext(p, sizeof(p), /*sendDuplicateOnUdp=*/false);
    }

    void dispatchIncoming(const uint8_t *plain, size_t len) {
        if (!plain || len < 1) return;
        const auto type = static_cast<MsgType>(plain[0]);
        if (type == MsgType::pong && len >= 9) {
            const uint64_t sentUs = readU64Le(plain + 1);
            const uint64_t nowUs = steadyNowUs();
            if (nowUs >= sentUs) {
                lastRttUs_.store(static_cast<uint32_t>(std::min<uint64_t>(nowUs - sentUs, 9999999ULL)));
            }
            return;
        }

        if (len < 3) return;
        const uint16_t padId = readU16Le(plain + 1);
        switch (type) {
            case MsgType::feedback_rumble:
                if (len >= 7 && callbacks_.onRumble) {
                    feedbackRecv_.fetch_add(1);
                    callbacks_.onRumble(padId, readU16Le(plain + 3), readU16Le(plain + 5));
                }
                break;
            case MsgType::feedback_rumble_triggers:
                if (len >= 7 && callbacks_.onRumbleTriggers) {
                    feedbackRecv_.fetch_add(1);
                    callbacks_.onRumbleTriggers(padId, readU16Le(plain + 3), readU16Le(plain + 5));
                }
                break;
            case MsgType::feedback_rgb_led:
                if (len >= 6 && callbacks_.onSetControllerLED) {
                    feedbackRecv_.fetch_add(1);
                    callbacks_.onSetControllerLED(padId, plain[3], plain[4], plain[5]);
                }
                break;
            case MsgType::feedback_adaptive_triggers:
                if (len >= 26 && callbacks_.onSetAdaptiveTriggers) {
                    feedbackRecv_.fetch_add(1);
                    callbacks_.onSetAdaptiveTriggers(
                        padId, plain[3], plain[4], plain[5], plain + 6, plain + 16);
                }
                break;
            case MsgType::feedback_motion_state:
                if (len >= 6 && callbacks_.onSetMotionEventState) {
                    feedbackRecv_.fetch_add(1);
                    callbacks_.onSetMotionEventState(padId, plain[3], readU16Le(plain + 4));
                }
                break;
            default:
                break;
        }
    }

    void rxLoop() {
        std::vector<uint8_t> tcpAcc;
        std::vector<uint8_t> udpBuf(2048);
        std::vector<uint8_t> plain;
        int64_t lastPingMs = steadyNowMs();

        while (!rxStop_.load()) {
            SocketHandle tcpFd = kInvalidSocket;
            SocketHandle udpFd = kInvalidSocket;
            {
                std::lock_guard<std::mutex> lk(socketMutex_);
                tcpFd = tcpSock_;
                udpFd = udpSock_;
            }

            bool didWork = false;

            if (tcpFd != kInvalidSocket) {
                uint8_t chunk[2048];
                const int n = static_cast<int>(recv(tcpFd, reinterpret_cast<char *>(chunk), sizeof(chunk), 0));
                if (n > 0) {
                    didWork = true;
                    tcpAcc.insert(tcpAcc.end(), chunk, chunk + n);
                    while (tcpAcc.size() >= 2) {
                        const uint16_t frameLen = readU16Le(tcpAcc.data());
                        if (frameLen == 0 || frameLen > 2048) {
                            tcpAcc.clear();
                            break;
                        }
                        if (tcpAcc.size() < 2 + frameLen) break;
                        if (openPacket(tcpAcc.data() + 2, frameLen, plain)) {
                            packetsRecv_.fetch_add(1);
                            dispatchIncoming(plain.data(), plain.size());
                        }
                        tcpAcc.erase(tcpAcc.begin(), tcpAcc.begin() + 2 + frameLen);
                    }
                } else if (n == 0) {
                    std::lock_guard<std::mutex> lk(socketMutex_);
                    if (tcpSock_ == tcpFd) {
                        closeSocketHandle(tcpSock_);
                        tcpSock_ = kInvalidSocket;
                        usingTcp_.store(false);
                    }
                }
            }

            if (udpFd != kInvalidSocket) {
                for (int reads = 0; reads < 16; ++reads) {
                    const int n = static_cast<int>(
                        recv(udpFd, reinterpret_cast<char *>(udpBuf.data()), static_cast<int>(udpBuf.size()), 0));
                    if (n <= 0) break;
                    didWork = true;
                    if (openPacket(udpBuf.data(), static_cast<size_t>(n), plain)) {
                        packetsRecv_.fetch_add(1);
                        dispatchIncoming(plain.data(), plain.size());
                    }
                }
            }

            const int64_t nowMs = steadyNowMs();
            if (nowMs - lastPingMs >= kPingIntervalMs) {
                lastPingMs = nowMs;
                sendPingLockedFree();
            }

            if (!didWork) {
#ifdef _WIN32
                WSAPOLLFD fds[2] {};
                ULONG nfds = 0;
                if (tcpFd != kInvalidSocket) {
                    fds[nfds].fd = tcpFd;
                    fds[nfds].events = POLLRDNORM;
                    ++nfds;
                }
                if (udpFd != kInvalidSocket) {
                    fds[nfds].fd = udpFd;
                    fds[nfds].events = POLLRDNORM;
                    ++nfds;
                }
                if (nfds > 0) {
                    WSAPoll(fds, nfds, 20);
                } else {
                    std::this_thread::sleep_for(std::chrono::milliseconds(10));
                }
#else
                struct pollfd fds[2] {};
                nfds_t nfds = 0;
                if (tcpFd != kInvalidSocket) {
                    fds[nfds].fd = tcpFd;
                    fds[nfds].events = POLLIN;
                    ++nfds;
                }
                if (udpFd != kInvalidSocket) {
                    fds[nfds].fd = udpFd;
                    fds[nfds].events = POLLIN;
                    ++nfds;
                }
                if (nfds > 0) {
                    poll(fds, nfds, 20);
                } else {
                    std::this_thread::sleep_for(std::chrono::milliseconds(10));
                }
#endif
            }
        }
    }

    std::mutex stateMutex_;
    std::mutex socketMutex_;
    std::array<uint8_t, kKeyBytes> key_ {};
    std::atomic<uint32_t> sessionId_{0};
    std::atomic<uint64_t> txNonce_{1};
    std::atomic<uint32_t> flushSeq_{0};
    std::atomic<bool> active_{false};
    std::atomic<bool> usingTcp_{false};
    std::atomic<bool> rxStop_{false};

    std::atomic<uint64_t> packetsSent_{0};
    std::atomic<uint64_t> packetsRecv_{0};
    std::atomic<uint64_t> authFailures_{0};
    std::atomic<uint64_t> feedbackRecv_{0};
    std::atomic<uint32_t> lastRttUs_{0};

    TurboFeedbackCallbacks callbacks_ {};
    std::array<PadTxState, kMaxGamepads> pads_ {};
    ReplayWindow64 rxReplay_;

    SocketHandle udpSock_ = kInvalidSocket;
    SocketHandle tcpSock_ = kInvalidSocket;
    std::thread rxThread_;
};

}  // namespace

extern "C" {

bool turboClientStart(
    const char *host,
    int udpPort,
    int tcpPort,
    uint32_t sessionId,
    const char *keyHex,
    const TurboFeedbackCallbacks *callbacks) {
    return TurboClientImpl::instance().start(host, udpPort, tcpPort, sessionId, keyHex, callbacks);
}

void turboClientStop(void) {
    TurboClientImpl::instance().stop();
}

bool turboClientIsActive(void) {
    return TurboClientImpl::instance().isActive();
}

TurboClientStats turboClientGetStats(void) {
    return TurboClientImpl::instance().stats();
}

bool turboClientSendGamepadArrival(
    uint8_t controllerNumber,
    uint8_t controllerType,
    uint16_t capabilities,
    uint32_t supportedButtons) {
    return TurboClientImpl::instance().sendArrival(
        controllerNumber, controllerType, capabilities, supportedButtons);
}

bool turboClientSendGamepadState(
    uint8_t controllerNumber,
    uint16_t activeMask,
    uint32_t buttons,
    uint8_t leftTrigger,
    uint8_t rightTrigger,
    int16_t leftStickX,
    int16_t leftStickY,
    int16_t rightStickX,
    int16_t rightStickY,
    uint8_t flags) {
    return TurboClientImpl::instance().sendState(
        controllerNumber, activeMask, buttons, leftTrigger, rightTrigger,
        leftStickX, leftStickY, rightStickX, rightStickY, flags);
}

bool turboClientSendGamepadMotion(
    uint8_t controllerNumber,
    uint8_t motionType,
    float x,
    float y,
    float z) {
    return TurboClientImpl::instance().sendMotion(controllerNumber, motionType, x, y, z);
}

bool turboClientSendGamepadTouch(
    uint8_t controllerNumber,
    uint8_t eventType,
    uint32_t pointerId,
    float x,
    float y,
    float pressure) {
    return TurboClientImpl::instance().sendTouch(controllerNumber, eventType, pointerId, x, y, pressure);
}

}  // extern "C"
