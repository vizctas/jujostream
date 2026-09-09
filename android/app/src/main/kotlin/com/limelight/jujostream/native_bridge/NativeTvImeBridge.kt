package com.limelight.jujostream.native_bridge

import android.app.Activity
import android.content.Context
import android.graphics.Color
import android.text.Editable
import android.text.InputFilter
import android.text.InputType
import android.text.TextWatcher
import android.util.Log
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.FrameLayout
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Invisible native input connection for Android TV system keyboards.
 *
 * This is intentionally not a keyboard. The installed IME remains fully in
 * charge of rendering and DPAD navigation; this bridge only supplies the
 * native EditText input target that Chromecast Gboard expects.
 */
class NativeTvImeBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    companion object {
        private const val CHANNEL = "com.jujostream/native_tv_ime"
        private const val TAG = "NativeTvIme"
    }

    private val channel = MethodChannel(messenger, CHANNEL)
    private var inputView: BridgeEditText? = null
    private var previousFocus: View? = null
    private var activeFieldId: String? = null
    private var suppressEvents = false

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "open" -> {
                open(call)
                result.success(null)
            }
            "close" -> {
                close(notifyDart = false)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun open(call: MethodCall) {
        val fieldId = call.argument<String>("fieldId") ?: return
        val initialText = call.argument<String>("text").orEmpty()
        val input = call.argument<String>("input").orEmpty()
        val action = call.argument<String>("action").orEmpty()
        val maxLength = call.argument<Int>("maxLength")

        close(notifyDart = false, restoreFocus = false)
        previousFocus = activity.currentFocus
        activeFieldId = fieldId
        Log.i(TAG, "Opening native system IME target for $fieldId")

        val editText = BridgeEditText(activity) { close(notifyDart = true) }.apply {
            isSingleLine = true
            setBackgroundColor(Color.TRANSPARENT)
            setTextColor(Color.TRANSPARENT)
            setHintTextColor(Color.TRANSPARENT)
            isCursorVisible = false
            alpha = 0.01f
            imeOptions = (if (action == "next") {
                EditorInfo.IME_ACTION_NEXT
            } else {
                EditorInfo.IME_ACTION_DONE
            }) or EditorInfo.IME_FLAG_NO_EXTRACT_UI
            inputType = when (input) {
                "email" -> InputType.TYPE_CLASS_TEXT or
                    InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS
                "password" -> InputType.TYPE_CLASS_TEXT or
                    InputType.TYPE_TEXT_VARIATION_PASSWORD
                "number" -> InputType.TYPE_CLASS_NUMBER
                else -> InputType.TYPE_CLASS_TEXT
            }
            filters = maxLength?.let { arrayOf(InputFilter.LengthFilter(it)) } ?: emptyArray()
            suppressEvents = true
            setText(initialText)
            setSelection(initialText.length)
            suppressEvents = false
            addTextChangedListener(object : TextWatcher {
                override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
                override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
                    if (!suppressEvents) emit("onChanged", mapOf("text" to s.toString()))
                }
                override fun afterTextChanged(s: Editable?) = Unit
            })
            setOnEditorActionListener { _, actionId, event ->
                val submitted = actionId == EditorInfo.IME_ACTION_NEXT ||
                    actionId == EditorInfo.IME_ACTION_DONE ||
                    (event?.keyCode == KeyEvent.KEYCODE_ENTER && event.action == KeyEvent.ACTION_UP)
                if (submitted) emit("onSubmitted")
                submitted
            }
        }

        inputView = editText
        val content = activity.findViewById<ViewGroup>(android.R.id.content)
        content.addView(editText, FrameLayout.LayoutParams(1, 1))
        editText.post {
            editText.requestFocus()
            val inputManager = activity.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
            inputManager.showSoftInput(editText, InputMethodManager.SHOW_IMPLICIT)
        }
    }

    private fun emit(method: String, extra: Map<String, Any?> = emptyMap()) {
        val fieldId = activeFieldId ?: return
        channel.invokeMethod(method, mapOf("fieldId" to fieldId) + extra)
    }

    private fun close(notifyDart: Boolean, restoreFocus: Boolean = true) {
        val view = inputView ?: return
        if (notifyDart) emit("onClosed")
        val inputManager = activity.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
        inputManager.hideSoftInputFromWindow(view.windowToken, 0)
        (view.parent as? ViewGroup)?.removeView(view)
        inputView = null
        activeFieldId = null
        Log.i(TAG, "Closed native system IME target")
        if (restoreFocus) previousFocus?.post { previousFocus?.requestFocus() }
        previousFocus = null
    }

    fun dispose() {
        close(notifyDart = false)
        channel.setMethodCallHandler(null)
    }

    private class BridgeEditText(
        context: Context,
        private val onImeDismissed: () -> Unit,
    ) : EditText(context) {
        override fun onKeyPreIme(keyCode: Int, event: KeyEvent): Boolean {
            if (keyCode == KeyEvent.KEYCODE_BACK && event.action == KeyEvent.ACTION_UP) {
                post(onImeDismissed)
            }
            return super.onKeyPreIme(keyCode, event)
        }
    }
}
