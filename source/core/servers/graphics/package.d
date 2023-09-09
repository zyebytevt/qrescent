module qrescent.core.servers.graphics;

public import qrescent.core.servers.graphics.window;

import std.string : fromStringz, splitLines;
import std.exception : enforce;
import std.algorithm : clamp, min;
import std.traits : isSomeString;

import gl3n.linalg;
import derelict.opengl;
import derelict.glfw3;

import qrescent.core.servers.language : tr;
import qrescent.core.exceptions;
import qrescent.core.engine;
import qrescent.core.qomproc;
import qrescent.resources.font;
import qrescent.resources.mesh;

/**
The GraphicsServer provides low-level functions for rendering, viewport
management, and access to the game window.
*/
struct GraphicsServer
{
    @disable this();
    @disable this(this);

public static:
    /**
    Changes the current viewport size.

    Params:
        width = The width of the new size in pixels.
        height = The height of the new size in pixels.

    Throws: `GraphicsException` on invalid viewport size.
    */
    void setViewportSize(int width, int height)
    {
        enforce!GraphicsException(width >= 1 && height >= 1, "Invalid size for viewport!".tr);

        _viewportSizeX = width;
        _viewportSizeY = height;

        if (_renderFBO > 0)
        {
            glDeleteFramebuffers(1, &_renderFBO);
		    glDeleteRenderbuffers(2, _renderBuffers.ptr);
        }

        glGenFramebuffers(1, &_renderFBO);
        glGenRenderbuffers(2, _renderBuffers.ptr);

        glBindRenderbuffer(GL_RENDERBUFFER, _renderBuffers[0]);
        glRenderbufferStorage(GL_RENDERBUFFER, GL_RGB8, _viewportSizeX, _viewportSizeY);
        glBindRenderbuffer(GL_RENDERBUFFER, _renderBuffers[1]);
        glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT, _viewportSizeX, _viewportSizeY);

        glBindFramebuffer(GL_FRAMEBUFFER, _renderFBO);
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, _renderBuffers[0]);
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, _renderBuffers[1]);
        glBindRenderbuffer(GL_RENDERBUFFER, 0);
        glBindFramebuffer(GL_FRAMEBUFFER, 0);

        glViewport(0, 0, _viewportSizeX, _viewportSizeY);

        _recalculateBlitDest();
    }

    /**
    Returns the current viewport size.

    Params:
        width = The variable to write the viewport width to.
        height = The variable to write the viewport height to.
    */
    void getViewportSize(out int width, out int height) @safe nothrow
    {
        width = _viewportSizeX;
        height = _viewportSizeY;
    }

    /**
    Generates vertices and indices for a text with the given font, to
    be used with a mesh to render text.

    Params:
        text = The text to use.
        font = The font to use.
        vertices = The variable to write the calculated vertices to.
        indices = The variable to write the calculated indices to.

    Throws: `GraphicsException` if either `text` or `font` is `null`.
    */
    void getTextVertices(String)(String text, Font font, out Vertex[] vertices, out uint[] indices,
        Font.Alignment alignment = Font.Alignment.left | Font.Alignment.top) @safe
        if (isSomeString!String)
    {
        enforce!GraphicsException(text && font, "Cannot create text vertices without text or font!".tr);

        int xPosition;
        int yPosition;

        // Check vertical alignment
        if (alignment & Font.Alignment.middle)
            yPosition = -font.getTextHeight(text) / 2;
        else if (alignment & Font.Alignment.bottom)
            yPosition = -font.getTextHeight(text);

        foreach (String line; text.splitLines)
        {
            // Check horizontal alignment
            if (alignment & Font.Alignment.left)
                xPosition = 0;
            else if (alignment & Font.Alignment.center)
                xPosition = -font.getTextWidth(line) / 2;
            else if (alignment & Font.Alignment.right)
                xPosition = -font.getTextWidth(line);

            for (size_t i; i < line.length; ++i)
            {
                Font.Character* character = line[i] in font.characters;
                if (!character)
                    break;

                int kerning = 1;
                if (xPosition > 0)
                {
                    foreach (ref Font.Kerning k; font.kernings)
                        if (k.first == line[i-1] && k.second == line[i])
                            kerning = k.amount;
                }

                immutable uint pageWidth = font.pages[character.page].width;
                immutable uint pageHeight = font.pages[character.page].height;

                // Get texture coordinates
                float u1 = cast(float) character.x / pageWidth;
                float v1 = cast(float) character.y / pageHeight;
                float u2 = u1 + cast(float) character.width / pageWidth;
                float v2 = v1 + cast(float) character.height / pageHeight;

                // Create vertices
                Vertex vx1 = Vertex(vec3(xPosition + character.xoffset + kerning, yPosition + character.yoffset, 0),
                    vec2(u1, v1));
                Vertex vx2 = Vertex(vec3(xPosition + character.xoffset + kerning, yPosition + character.height
                    + character.yoffset, 0), vec2(u1, v2));
                Vertex vx3 = Vertex(vec3(xPosition + character.width + character.xoffset + kerning, yPosition
                    + character.height + character.yoffset, 0), vec2(u2, v2));
                Vertex vx4 = Vertex(vec3(xPosition + character.width + character.xoffset + kerning, yPosition
                    + character.yoffset, 0), vec2(u2, v1));

                // Create indices
                immutable size_t l = vertices.length;
                indices ~= cast(uint[]) [l+3, l, l+1, l+3, l+1, l+2];

                // Add vertices
                vertices ~= [vx1, vx2, vx3, vx4];

                xPosition += character.xadvance + kerning;
            }
            
            yPosition += font.common.lineHeight;
        }
    }

    /// The current game window.
    @property Window window() nothrow @safe @nogc { return _window; } // @suppress(dscanner.style.doc_missing_returns)

package(qrescent.core) static:
    void _initialize()
    {
        Qomproc.println("GraphicsServer initializing...".tr);

        Qomproc.registerQVAR("vid_scalemode", QVAR(&_scaleMode, "How the game should be scaled up to the window.".tr,
            QVAR.Flags.archive, function void(void* value)
        {
            _scaleMode = clamp(_scaleMode, 0, 2);
            _recalculateBlitDest();
        }));

        // Create window for OpenGL context
        _window = new Window(EngineCore.projectSettings.windowSize.x, EngineCore.projectSettings.windowSize.y,
            EngineCore.projectSettings.windowTitle);
        _window.setSwapInterval(0);

        glfwMakeContextCurrent(_window.glfwWindow);
        DerelictGL3.reload();

        //glfwGetWindowSize(_window.glfwWindow, &_windowSizeX, &_windowSizeY);
        glfwSetWindowSizeCallback(_window.glfwWindow, &glfwWindowSizeCallback);

        // Enable graphical debug output
        glfwSetErrorCallback(&glfwErrorCallback);
        glEnable(GL_DEBUG_OUTPUT);
        glDebugMessageCallback(&glErrorCallback, null);

        // Set OpenGL properties to their correct values
        glEnable(GL_BLEND);
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

        glEnable(GL_CULL_FACE);
        glCullFace(GL_BACK);

        glEnable(GL_DEPTH_TEST);

        glEnable(GL_TEXTURE_CUBE_MAP);
        glEnable(GL_TEXTURE_2D);
    }

    void _shutdown()
    {
        Qomproc.println("GraphicsServer shutting down...".tr);

        _window.destroy();

        glDeleteFramebuffers(1, &_renderFBO);
		glDeleteRenderbuffers(2, _renderBuffers.ptr);

        Qomproc.unregisterQVAR("vid_scalemode");
    }

    void _prepareRender() nothrow
    {
        glBindFramebuffer(GL_FRAMEBUFFER, _renderFBO);
        glClearColor(0.4, 0.14, 0.6, 1);
    }

    void _finishRender() nothrow
    {
        glBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0);
        
        glClearColor(0, 0, 0, 1);
        glClear(GL_COLOR_BUFFER_BIT);
        
        glBlitFramebuffer(0, 0, _viewportSizeX, _viewportSizeY, _blitX, _blitY, _blitX + _blitW, _blitY + _blitH,
            GL_COLOR_BUFFER_BIT, GL_NEAREST);

        _window.swapBuffers();
    }

private static:
    Window _window;
    uint _renderFBO;
    uint[2] _renderBuffers;

    int _viewportSizeX, _viewportSizeY;
    int _blitX, _blitY, _blitW, _blitH;
    int _scaleMode;

    void _recalculateBlitDest() nothrow
    {
        int winWidth, winHeight; // @suppress(dscanner.suspicious.unmodified)
        _window.getSize(winWidth, winHeight);

        switch (_scaleMode)
        {
            case 0: // center
                _blitX = winWidth / 2 - _viewportSizeX / 2;
                _blitY = winHeight / 2 - _viewportSizeY / 2;
                _blitW = _viewportSizeX;
                _blitH = _viewportSizeY;
                break;

            case 1: // aspect
                immutable float scale = min(cast(float) winWidth / _viewportSizeX,
                    cast(float) winHeight / _viewportSizeY);
                
                immutable int sizeX = cast(int) (_viewportSizeX * scale);
                immutable int sizeY = cast(int) (_viewportSizeY * scale);

                _blitX = winWidth / 2 - sizeX / 2;
                _blitY = winHeight / 2 - sizeY / 2;
                _blitW = sizeX;
                _blitH = sizeY;
                break;

            case 2: // fill
                _blitX = 0;
                _blitY = 0;
                _blitW = winWidth;
                _blitH = winHeight;
                break;

            default:
                assert(false, "GraphicsServer: _scaleMode has invalid value!");
        }
    }
}

private:

extern(C) void glfwWindowSizeCallback(GLFWwindow* window, int width, int height) nothrow // @suppress(dscanner.suspicious.unused_parameter)
{
    GraphicsServer._recalculateBlitDest();
}

extern(C) void glfwErrorCallback(int nr, const char* msg) nothrow
{
    Qomproc.printfln("*** GLFW error #%d: %s", nr, msg.fromStringz);
}

extern(C) void glErrorCallback(GLenum source, GLenum type, uint id, GLenum severity, GLsizei length, // @suppress(dscanner.suspicious.unused_parameter)
    const char* message, const void* userParam) nothrow
{
    glGetError();

    string typeStr, severityStr;

    switch (type)
    {
        case GL_DEBUG_TYPE_ERROR:
            typeStr = "Error";
            break;
        
        case GL_DEBUG_TYPE_DEPRECATED_BEHAVIOR:
            typeStr = "Deprecated Behavior";
            break;
        
        case GL_DEBUG_TYPE_UNDEFINED_BEHAVIOR:
            typeStr = "Undefined Behavior";
            break;

        case GL_DEBUG_TYPE_PERFORMANCE:
            typeStr = "Performance";
            break;

        case GL_DEBUG_TYPE_OTHER:
        default:
            return;
    }

    switch (severity)
    {
        case GL_DEBUG_SEVERITY_LOW:
            severityStr = "info";
            break;

        case GL_DEBUG_SEVERITY_MEDIUM:
            severityStr = "warning";
            break;

        case GL_DEBUG_SEVERITY_HIGH:
            severityStr = "error";
            break;

        default:
            severityStr = "notice";
            break;
    }

    Qomproc.printfln("*** OpenGL %s (%s):", severityStr, typeStr);
    Qomproc.println(cast(string) message[0..length]);
}