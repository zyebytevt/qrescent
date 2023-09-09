module qrescent.core.servers.graphics.window;

import std.exception : enforce;
import std.string : toStringz;

import derelict.opengl;
import derelict.glfw3;

import qrescent.core.servers.language : tr;
import qrescent.core.exceptions;

/**
Settings struct used for window initialization.
*/
struct WindowSettings
{
    /**
    Specifies whether the windowed mode window will be resizable by the user.
    This hint is ignored for full screen and undecorated windows.
    */
    bool resizable = true;
    /**
    Specifies whether the windowed mode window will be initially visible.
    This hint is ignored for full screen windows.
    */
    bool visible = true;
    /**
    Specifies whether the windowed mode window will have window decorations
    such as a border, a close widget, etc.
    An undecorated window will not be resizable by the user but will still
    allow the user to generate close events on some platforms.
    This hint is ignored for full screen windows.
    */
    bool decorated = true;
    /**
    Specifies whether the windowed mode window will be given input focus when created.
    This hint is ignored for full screen and initially hidden windows.
    */
    bool focused = true;
    /**
    Specifies whether the full screen window will automatically iconify and restore
    the previous video mode on input focus loss.
    This hint is ignored for windowed mode windows.
    */
    bool autoIconify = true;
    /**
    Specifies whether the windowed mode window will be floating above other regular windows,
    also called topmost or always-on-top. This is intended primarily for debugging purposes
    and cannot be used to implement proper full screen windows.
    This hint is ignored for full screen windows.
    */
    bool floating = false;
    /**
    Specifies whether the windowed mode window will be maximized when created.
    This hint is ignored for full screen windows.
    */
    bool maximized = false;

    /**
    The monitor to use for full screen mode, or `null` for windowed mode.
    */
    GLFWmonitor* monitor = null;
    /**
    The window whose context to share resources with, or `null` to not share resources.
    */
    GLFWwindow* share = null;
}

/**
A wrapper class for a GLFW window, providing most basic
functionality for it. If some settings aren't covered by
this, you can get the GLFWwindow pointer with `glfwWindow`.
*/
class Window
{
public:
    /**
    Creates a new window.

    Params:
        width = The width of the new window, in pixels.
        height = The height of the new window, in pixels.
        title = The title of the new window.
        settings = The settings to create the new window with.
    */
    this(int width, int height, string title, WindowSettings settings = WindowSettings.init) @trusted
    {
        // Pass values through from settings var
        glfwWindowHint(GLFW_RESIZABLE, settings.resizable);
        glfwWindowHint(GLFW_VISIBLE, settings.visible);
        glfwWindowHint(GLFW_DECORATED, settings.decorated);
        glfwWindowHint(GLFW_FOCUSED, settings.focused);
        glfwWindowHint(GLFW_AUTO_ICONIFY, settings.autoIconify);
        glfwWindowHint(GLFW_FLOATING, settings.floating);
        glfwWindowHint(GLFW_MAXIMIZED, settings.maximized);

        _window = glfwCreateWindow(width, height, title.toStringz, settings.monitor, settings.share);
        enforce!GraphicsException(_window, "Failed to create window.".tr);
    }

    ~this() nothrow @trusted @nogc
    {
        glfwDestroyWindow(_window);
    }

    /**
    Swaps the internal display buffers.
    */
    void swapBuffers() nothrow @trusted @nogc
    {
        glfwSwapBuffers(_window);
    }

    /**
    Marks the context of this window as the current context.
    Useful when managing multiple windows.
    */
    void makeContextCurrent() nothrow @trusted @nogc
    {
        glfwMakeContextCurrent(_window);
    }

    /**
    Sets the swap interval for the current context, i.e. the number
    of screen updates to wait from the time `swapBuffers` was called
    before swapping and returning.

    Params:
        interval = The minimum number of screen updates to wait for.
    */
    void setSwapInterval(int interval) nothrow @trusted @nogc
    {
        makeContextCurrent();
        glfwSwapInterval(interval);
    }

    /**
    Get the current size of the window.

    Params:
        width = The variable to write the width to.
        height = The variable to write the height to.
    */
    void getSize(out int width, out int height) nothrow @trusted @nogc
    {
        glfwGetWindowSize(_window, &width, &height);
    }

    /// If the user has requested that this window should close (Alt-F4, pressing X etc.)
    @property bool shouldClose() nothrow @trusted @nogc // @suppress(dscanner.style.doc_missing_returns)
    {
        return cast(bool) glfwWindowShouldClose(_window);
    }

    /// The pointer to the low-level GLFW window.
    @property GLFWwindow* glfwWindow() pure nothrow @safe @nogc { return _window; } // @suppress(dscanner.style.doc_missing_returns)

private:
    GLFWwindow* _window;
}
