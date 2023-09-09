module qrescent.core.servers.input;

import std.string : format;
import std.exception : enforce, collectException;

import derelict.glfw3;
import gl3n.linalg : vec2;

import qrescent.core.servers.language : tr;
import qrescent.core.servers.graphics;
import qrescent.core.exceptions;
import qrescent.core.qomproc;
import qrescent.core.qomprocgui;

/**
The InputServer provides low-level functions for cursor management
and handles key bindings via Qomproc.
*/
struct InputServer
{
	@disable this();
	@disable this(this);

public static:
    /// Cursor behavior modes.
    enum CursorMode
    {
        normal = GLFW_CURSOR_NORMAL, /// Normal behavior.
        hidden = GLFW_CURSOR_HIDDEN, /// Cursor is hidden, but still behaving normally.
        disabled = GLFW_CURSOR_DISABLED /// Cursor is hidden and locked inside the window.
    }

    /**
    Gets the scancode for the given key name.

    Params:
        name = The name of the key.

    Returns: The scancode of the given key, or `0` if the key was not found.
    */
    int getKeyForName(string name)
    {
        foreach (ref immutable KeyName kn; _keyNames)
            if (kn.name == name)
                return kn.scancode;

        return 0;
    }

    /**
    Gets the key name for the given scancode.

    Params:
        key = The scancode of the key.

    Returns: The key name of the given scancode, or `null` if the scancode was not found.
    */
    string getNameForKey(int key)
    {
        foreach (ref immutable KeyName kn; _keyNames)
            if (kn.scancode == key)
                return kn.name;

        return null;
    }

    /// The behavior mode of the cursor.
    @property void cursorMode(CursorMode mode) nothrow @trusted // @suppress(dscanner.style.doc_missing_params)
    {
        _cursorMode = mode;
        glfwSetInputMode(GraphicsServer.window.glfwWindow, GLFW_CURSOR, mode);
    }

    /// ditto
    @property CursorMode cursorMode() nothrow @safe { return _cursorMode; } // @suppress(dscanner.style.doc_missing_returns)

    /// The current position of the cursor.
    @property vec2 cursorPosition() nothrow @trusted // @suppress(dscanner.style.doc_missing_returns)
    {
        double xpos, ypos;
        int winWidth, winHeight; // @suppress(dscanner.suspicious.unmodified) (out variables)
        int viewWidth, viewHeight; // @suppress(dscanner.suspicious.unmodified) (out variables)

        glfwGetCursorPos(GraphicsServer.window.glfwWindow, &xpos, &ypos);
        GraphicsServer.window.getSize(winWidth, winHeight);
        GraphicsServer.getViewportSize(viewWidth, viewHeight);

        xpos *= cast(float) viewWidth / winWidth;
        ypos *= cast(float) viewHeight / winHeight;

        return vec2(xpos, ypos);
    }

    /// Current key to command bindings.
	@property const(string[int]) bindings() // @suppress(dscanner.style.doc_missing_returns)
	{
		return cast(const(string[int])) _bindings;
	}

package(qrescent.core) static:
    void _initialize() // @suppress(dscanner.style.doc_missing_throw)
	{
        Qomproc.println("InputServer initializing...".tr);
        assert(GraphicsServer.window, "Cannot initialize InputServer with GraphicsServer uninitialized.");

		with (Qomproc)
		{
			registerQCMD("bind", QCMD(delegate void(string[] args, Qomproc.CommandSource cmdsrc) // @suppress(dscanner.suspicious.unused_parameter)
					{
						enforce!QomprocException(args.length < 4, "Too many arguments.".tr);
						
						if (args.length == 1)
						{
							foreach (int key; _bindings.keys)
								printfln("%s = %s", getNameForKey(key), _bindings[key]);
							
							return;
						}
						
						int key = getKeyForName(args[1]);
						enforce!QomprocException(key > 0, "Key '%s' does not exist.".tr.format(args[1]));
						
						if (args.length == 2 || (args.length == 3 && args[2].length == 0))
						{
							if (key in _bindings)
								printfln("This key is bound to '%s'.".tr, _bindings[key]);
							else
								println("This key is not bound.".tr);
							
							return;
						}
						
						enforce!QomprocException(args[2][0] != '-',
							"Cannot bind release command; bind press command ('+') instead.".tr);
						
						_bindings[key] = args[2];
					},
					"Binds a key to a QCMD. With no arguments, lists all bindings.".tr));
			
			registerQCMD("bindsingle", QCMD(delegate void(string[] args, Qomproc.CommandSource cmdsrc)
					{
						enforce!QomprocException(args.length == 3 && args[2].length > 0,
							"Expected key and command to single bind.".tr);
						
						int key = getKeyForName(args[1]);
						enforce!QomprocException(key > 0, "Key '%s' does not exist.".tr.format(args[1]));
						enforce!QomprocException(args[2][0] != '-',
							"Cannot bind release command; bind press command ('+') instead.".tr);
						
						foreach (int key, string command; _bindings)
						{
							if (command == args[2])
								_bindings.remove(key);
						}
						
						_bindings[key] = args[2];
					},
					"Binds a key to a command, and unbinds all other keys with the same one.".tr));
			
			registerQCMD("unbind", QCMD(delegate void(string[] args, Qomproc.CommandSource cmdsrc)
					{
						enforce!QomprocException(args.length >= 2, "Too few arguments.".tr);
						
						foreach (string arg; args[1 .. $])
						{
							immutable key = getKeyForName(arg);
							
							if (key == 0)
								printfln("Key '%s' does not exist.".tr, arg);
							else
								_bindings.remove(key);
						}
					},
					"Unbinds one or more keys from their commands.".tr));
			
			registerQCMD("unbindall", QCMD(delegate void(string[] args, Qomproc.CommandSource cmdsrc) // @suppress(dscanner.suspicious.unused_parameter)
					{
						foreach (int key; _bindings.keys)
							_bindings.remove(key);
					},
					"Unbinds all keys from their commands.".tr));
		}

        glfwSetKeyCallback(GraphicsServer.window.glfwWindow, &keyCallback);
        glfwSetCharCallback(GraphicsServer.window.glfwWindow, &charCallback);
        glfwSetMouseButtonCallback(GraphicsServer.window.glfwWindow, &mouseButtonCallback);
	}
	
	void _shutdown()
	{
        Qomproc.println("InputServer shutting down...".tr);

		with (Qomproc)
		{
			unregisterQCMD("bind");
			unregisterQCMD("bindsingle");
			unregisterQCMD("unbind");
			unregisterQCMD("unbindall");
		}
	}

private static:
    enum mouseOffset = 1000;

    struct KeyName
    {
        int scancode;
        string name;
    }

    CursorMode _cursorMode;
    string[int] _bindings;
    immutable KeyName[] _keyNames = [
        { mouseOffset + GLFW_MOUSE_BUTTON_LEFT, "mouse1" },
        { mouseOffset + GLFW_MOUSE_BUTTON_RIGHT, "mouse2" },
        { mouseOffset + GLFW_MOUSE_BUTTON_MIDDLE, "mouse3" },

        { GLFW_KEY_0, "0" },
        { GLFW_KEY_1, "1" },
        { GLFW_KEY_2, "2" },
        { GLFW_KEY_3, "3" },
        { GLFW_KEY_4, "4" },
        { GLFW_KEY_5, "5" },
        { GLFW_KEY_6, "6" },
        { GLFW_KEY_7, "7" },
        { GLFW_KEY_8, "8" },
        { GLFW_KEY_9, "9" },
        { GLFW_KEY_0, "0" },
        { GLFW_KEY_A, "a" },
        { GLFW_KEY_B, "b" },
        { GLFW_KEY_C, "c" },
        { GLFW_KEY_D, "d" },
        { GLFW_KEY_E, "e" },
        { GLFW_KEY_F, "f" },
        { GLFW_KEY_G, "g" },
        { GLFW_KEY_H, "h" },
        { GLFW_KEY_I, "i" },
        { GLFW_KEY_J, "j" },
        { GLFW_KEY_K, "k" },
        { GLFW_KEY_L, "l" },
        { GLFW_KEY_M, "m" },
        { GLFW_KEY_N, "n" },
        { GLFW_KEY_O, "o" },
        { GLFW_KEY_P, "p" },
        { GLFW_KEY_Q, "q" },
        { GLFW_KEY_R, "r" },
        { GLFW_KEY_S, "s" },
        { GLFW_KEY_T, "t" },
        { GLFW_KEY_U, "u" },
        { GLFW_KEY_V, "v" },
        { GLFW_KEY_W, "w" },
        { GLFW_KEY_X, "x" },
        { GLFW_KEY_Y, "y" },
        { GLFW_KEY_Z, "z" },
        { GLFW_KEY_F1, "f1" },
        { GLFW_KEY_F2, "f2" },
        { GLFW_KEY_F3, "f3" },
        { GLFW_KEY_F4, "f4" },
        { GLFW_KEY_F5, "f5" },
        { GLFW_KEY_F6, "f6" },
        { GLFW_KEY_F7, "f7" },
        { GLFW_KEY_F8, "f8" },
        { GLFW_KEY_F9, "f9" },
        { GLFW_KEY_F10, "f10" },
        { GLFW_KEY_F11, "f11" },
        { GLFW_KEY_F12, "f12" },
        { GLFW_KEY_TAB, "tab" },
        { GLFW_KEY_ENTER, "enter" },
        { GLFW_KEY_SPACE, "space" },
        { GLFW_KEY_BACKSPACE, "backspace" },
        { GLFW_KEY_UP, "uparrow" },
        { GLFW_KEY_DOWN, "downarrow" },
        { GLFW_KEY_LEFT, "leftarrow" },
        { GLFW_KEY_RIGHT, "rightarrow" },
        { GLFW_KEY_LEFT_ALT, "leftalt" },
        { GLFW_KEY_LEFT_CONTROL, "leftctrl" },
        { GLFW_KEY_LEFT_SHIFT, "leftshift" },
        { GLFW_KEY_RIGHT_ALT, "rightalt" },
        { GLFW_KEY_RIGHT_CONTROL, "rightctrl" },
        { GLFW_KEY_RIGHT_SHIFT, "rightshift" },
        { GLFW_KEY_INSERT, "ins" },
        { GLFW_KEY_DEL, "del" },
        { GLFW_KEY_PAGE_DOWN, "pgdn" },
        { GLFW_KEY_PAGE_UP, "pgup" },
        { GLFW_KEY_HOME, "home" },
        { GLFW_KEY_END, "end" },
        { GLFW_KEY_PAUSE, "pause" },
        { GLFW_KEY_SEMICOLON, "semicolon" },
        { GLFW_KEY_PERIOD, "period" },
        { GLFW_KEY_COMMA, "comma" },
        { GLFW_KEY_MINUS, "minus" },
        { GLFW_KEY_ESCAPE, "escape" },
        { GLFW_KEY_GRAVE_ACCENT, "grave" }
    ];
}

private:

extern (C) void keyCallback(GLFWwindow* window, int key, int scancode, int action, int mods) nothrow
{
    if (QomprocGUI.visible)
    {
        QomprocGUI._keyCallback(key, scancode, action, mods);
        return;
    }

    if (!(key in InputServer._bindings))
        return;

    string command = InputServer._bindings[key];

    if (action == GLFW_PRESS)
        Qomproc.append(command);
    else if (action == GLFW_RELEASE && command[0] == '+')
        Qomproc.append("-" ~ command[1 .. $]);
}

extern (C) void mouseButtonCallback(GLFWwindow* window, int button, int action, int mods) nothrow // @suppress(dscanner.suspicious.unused_parameter)
{
    if (QomprocGUI.visible)
        return;

    immutable int key = InputServer.mouseOffset + button;

    if (!(key in InputServer._bindings))
        return;

    string command = InputServer._bindings[key];

    if (action == GLFW_PRESS)
        Qomproc.append(command);
    else if (action == GLFW_RELEASE && command[0] == '+')
        Qomproc.append("-" ~ command[1 .. $]);
}

extern(C) void charCallback(GLFWwindow* window, uint codepoint) nothrow
{
    if (QomprocGUI.visible)
    {
        QomprocGUI._charCallback(codepoint);
        return;
    }
}