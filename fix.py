with open("android/app/src/main/kotlin/com/limelight/jujostream/native_bridge/VideoDecoderRenderer.kt", "r") as f:
    content = f.read()

content = content.replace("private var redrawRateFps = 60", "private var redrawRateFps = 60\n    private var activeMimeType = \"\"")
content = content.replace("val mimeType = StreamConstants.mimeTypeForFormat(videoFormat) ?: run {", "activeMimeType = StreamConstants.mimeTypeForFormat(videoFormat) ?: run {")
content = content.replace("mimeType ==", "activeMimeType ==")
content = content.replace("(mimeType)", "(activeMimeType)")
content = content.replace("decodersByMime[mimeType]", "decodersByMime[activeMimeType]")
content = content.replace("createDecoderByType(mimeType)", "createDecoderByType(activeMimeType)")
content = content.replace("Surface(textureEntry!!.surfaceTexture())", "Surface(textureEntry!!.surfaceTexture().apply { setDefaultBufferSize(width, height) })")
content = content.replace("if (!submitCsdBuffers()) return DR_NEED_IDR", "if (!submittedCsd && !submitCsdBufcontent = content.replace("if (!submitCsdBuffers()) return DR_NEED_IDR", "if (!submittedCsd && !submitCsdBufconteUFcontent = content.replsecontent = content.replace("if (!submitCsdBuffers()) return DR_NEED_IDR", "if (!submittedCsd && !submitCsdBufcontent = content.repla
oooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo }'ooooooooooooooooooooooooooooooooooooooooooooooooooooooooo snapoooooooooooooooooooooooooooooooooooooooooooooooooooooooo, "Nooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo   oooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooot = ooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooite(content)
