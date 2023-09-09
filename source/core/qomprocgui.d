module qrescent.core.qomprocgui;

import std.string : splitLines, startsWith, strip;
import std.range : chunks, array;
import std.algorithm : map, min, max;
import std.conv : to;
import std.exception : assumeWontThrow;
import std.typecons : Tuple;

import derelict.opengl;
import derelict.glfw3;
import gl3n.linalg;

import qrescent.core.servers.language : tr;
import qrescent.core.servers.graphics;
import qrescent.core.qomproc;
import qrescent.resources.loader;
import qrescent.resources.shader;
import qrescent.resources.font;
import qrescent.resources.texture;
import qrescent.resources.mesh;
import qrescent.resources.sprite;
import qrescent.resources.material;

/**
Provides interactions with the graphical representation of the Qomproc.
*/
struct QomprocGUI
{
    @disable this();
    @disable this(this);

public static:
    /// If the Qomproc is currently visible.
    @property bool visible() @nogc @trusted nothrow { return _visible; } // @suppress(dscanner.style.doc_missing_returns)
    /// ditto
    @property void visible(bool value) @trusted // @suppress(dscanner.style.doc_missing_params)
    {
        _visible = _fullscreen || value;

        if (_visible)
        {
            _bufferOffset = 0;
            _updateBufferMesh();
        }

        _notifyLines.length = 0;
        _updateNotifyLinesMesh();
    }

    /// If the Qomproc is currently in full-screen.
    @property bool fullscreen() @nogc @trusted nothrow { return _fullscreen; } // @suppress(dscanner.style.doc_missing_returns)
    /// ditto
    @property void fullscreen(bool value) @trusted // @suppress(dscanner.style.doc_missing_params)
    {
        _fullscreen = value;
        _bufferOffset = 0;
        _updateBufferMesh();

        if (value)
            visible = true;
    }

package(qrescent.core) static:
    void _initialize()
    {
        Qomproc.println("QomprocGUI initializing...".tr);

        _background = new Sprite(cast(Texture2D) ResourceLoader.load("res://textures/conback.png"));
        _font = cast(Font) ResourceLoader.load("res://fonts/qomproc.qft");
        _shader = cast(ShaderProgram) ResourceLoader.load("res://shaders/unshaded.shd");

        _charWidth = _font.getTextWidth(" ");

        _lineMaxLength = 800 / _charWidth;
        _inputMaxLength = _lineMaxLength - 2;
        _nrLinesAtHalf = (300 / _font.common.lineHeight) - 2;
        _nrLinesAtFullscreen = (600 / _font.common.lineHeight) - 2;
        
        _projectionMatrix = mat4.orthographic(0, 800, 600, 0, -1, 1);
        _viewMatrix = mat4.identity;

        Qomproc.registerQCMD("toggleconsole", QCMD(delegate void(string[] args, Qomproc.CommandSource cmdsrc) // @suppress(dscanner.suspicious.unused_parameter)
        {
            visible = !visible;
        },
        "Toggles the visibility of the console.".tr));

        Qomproc.registerQCMD("clear", QCMD(delegate void(string[] args, Qomproc.CommandSource cmdsrc)
        {
            _buffer[] = "";
            _bufferOffset = 0;
            _updateBufferMesh();
        },
        "Clears the console.".tr));

        Qomproc.registerQCMD("condump", QCMD(delegate void(string[] args, Qomproc.CommandSource cmdsrc)
        {
            import qrescent.core.vfs : VFS, IVFSFile;

            dstring[] bufferContents = _buffer[0.._bufferSize];
            
            scope IVFSFile outputFile = VFS.getFile("user://condump.txt", "w");
            foreach_reverse (dstring line; bufferContents)
                outputFile.write(line ~ "\n");

            Qomproc.println("Content dumped to user://condump.txt.".tr);
        },
        "Dumps the contents of the console into a file.".tr));

        Qomproc.registerQVAR("con_showspeed", QVAR(&_showSpeed,
            "How fast the Qomproc moves when showing or hiding, in pixels.".tr, QVAR.Flags.archive));
        Qomproc.registerQVAR("con_notifylines", QVAR(&_notifyLinesNr, "How many notify lines are displayed at once.".tr,
            QVAR.Flags.archive));
        Qomproc.registerQVAR("con_notifytime", QVAR(&_notifyLinesTime, "How many frames a notify line stays visible.".tr,
            QVAR.Flags.archive));

        _notifyLinesMesh = new Mesh([], [], Mesh.DrawMethod.dynamic);
        _bufferMesh = new Mesh([], [], Mesh.DrawMethod.dynamic);
        _inputMesh = new Mesh([], [], Mesh.DrawMethod.dynamic);
        _updateInputMesh();

        {
            scope Vertex[] vertices;
            scope uint[] indices;
            GraphicsServer.getTextVertices("_", _font, vertices, indices);
            _cursorMesh = new Mesh(vertices, indices);
        }
    }

    /**
    Shuts down the graphical Qomproc representation.
    */
    void _shutdown()
    {
        Qomproc.println("QomprocGUI shutting down...".tr);

        Qomproc.unregisterQCMD("toggleconsole");
        Qomproc.unregisterQCMD("clear");
        Qomproc.unregisterQCMD("condump");
        Qomproc.unregisterQVAR("con_showspeed");
        Qomproc.unregisterQVAR("con_notifylines");
        Qomproc.unregisterQVAR("con_notifytime");

        _font = null;
        _shader = null;
        _background.destroy();
        _bufferMesh.destroy();
        _inputMesh.destroy();
    }

    void _update()
    {
        if (_visible)
        {
            immutable int target = _fullscreen ? 0 : -300;

            if (_position < target)
                _position += _showSpeed;
            
            if (_position > target)
                _position = target;
        }
        else
        {
            if (_position > -600)
                _position -= _showSpeed;

            if (_position < -600)
                _position = -600;
        }
    }

    void _render()
    {
        // Draw notify lines if Qomproc is not visible
        if (!_visible)
        {
            _shader.bind();
            _shader.setUniform("projection", _projectionMatrix);
            _shader.setUniform("transform", mat4.translation(2, 2, 0));
            _shader.setUniform("view", _viewMatrix);
            _shader.setUniform("texUseFlags", cast(uint) Material.TextureUseFlags.albedo);
            _font.pages[0].bind();
            _notifyLinesMesh.bind();
            _notifyLinesMesh.draw();

            for (size_t i; i < _notifyLines.length; ++i)
                _notifyLines[i].time--;

            while (_notifyLines.length > 0 && _notifyLines[0].time <= 0)
            {
                _notifyLines = _notifyLines[1 .. $];
                _notifyLinesMeshNeedsUpdate = true;
            }
        }

        if (_notifyLinesMeshNeedsUpdate)
        {
            _updateNotifyLinesMesh();
            _notifyLinesMeshNeedsUpdate = false;
        }

        // If Qomproc is not visible at all, end here
        if (_position <= -600)
            return;
        
        if (_bufferMeshNeedsUpdate)
        {
            _updateBufferMesh();
            _bufferMeshNeedsUpdate = false;
        }

        glDisable(GL_DEPTH_TEST);

        // Draw the background
        _shader.bind();
        _shader.setUniform("projection", _projectionMatrix);
        _shader.setUniform("transform", mat4.translation(0, _position, 0));
        _shader.setUniform("view", _viewMatrix);
        _shader.setUniform("texUseFlags", cast(uint) Material.TextureUseFlags.albedo);
        _background.texture.bind();
        _background.mesh.bind();
        _background.mesh.draw();

        // Draw the buffer
        _shader.setUniform("transform", mat4.translation(4, _position + (_fullscreen ? 4 : 304), 0));
        _font.pages[0].bind();
        _bufferMesh.bind();
        _bufferMesh.draw();

        // Draw the input string
        _shader.setUniform("transform", mat4.translation(4, _position + 568, 0));
        _inputMesh.bind();
        _inputMesh.draw();

        // Draw the flashing cursor
        if (++_cursorFlashCounter / 16 % 2 == 0)
        {
            _shader.setUniform("transform", mat4.translation(4 + _charWidth * (_cursor - _inputOffset + 2),
                _position + 568, 0));
            _cursorMesh.bind();
            _cursorMesh.draw();
        }
    }

    void _keyCallback(int key, int scancode, int action, int mods) nothrow // @suppress(dscanner.suspicious.unused_parameter)
    {
        if (action != GLFW_PRESS && action != GLFW_REPEAT)
            return;

        try
        {
            switch (key)
            {
                case GLFW_KEY_ESCAPE:
                    visible = false;
                    break;

                case GLFW_KEY_BACKSPACE:
                    if (_cursor > 0)
                    {
                        _input = _input[0 .. _cursor - 1] ~ _input[_cursor .. $];
                        _cursor--;
                        _cursorFlashCounter = 0;
                        _updateInputMesh();
                        _inCurrentCompletion = false;
                    }
                    break;

                case GLFW_KEY_DELETE:
                    if (_cursor != _input.length)
                    {
                        _input = _input[0 .. _cursor] ~ _input[_cursor + 1 .. $];
                        _cursorFlashCounter = 0;
                        _updateInputMesh();
                        _inCurrentCompletion = false;
                    }
                    break;

                case GLFW_KEY_ENTER:
                    if (_input.length == 0)
                        return;
                    
                    Qomproc.println("> " ~ _input);
                    Qomproc.append(_input);

                    _historyBackPointer = 0;
                    _historyBuffer.buffer[_historyBuffer.head] = _input.strip;
                    _historyBuffer.head = (_historyBuffer.head + 1) % _historyBuffer.buffer.length;

                    if (_historyBuffer.length < _historyBuffer.buffer.length)
                        _historyBuffer.length++;

                    _bufferOffset = 0;
                    _inputOffset = 0;
                    _input = "";
                    _cursor = 0;
                    _inCurrentCompletion = false;
                    _updateInputMesh();
                    break;

                case GLFW_KEY_RIGHT:
                    if (_cursor < _input.length)
                    {
                        _cursor++;
                        _cursorFlashCounter = 0;
                    }
                    break;

                case GLFW_KEY_LEFT:
                    if (_cursor > 0)
                    {
                        _cursor--;
                        _cursorFlashCounter = 0;
                    }
                    break;

                case GLFW_KEY_HOME:
                    _cursor = 0;
                    _cursorFlashCounter = 0;
                    break;

                case GLFW_KEY_END:
                    _cursor = cast(int) _input.length;
                    _cursorFlashCounter = 0;
                    break;

                case GLFW_KEY_PAGEUP:
                    _bufferOffset = cast(ushort) min(_bufferOffset + 4, min(_bufferSize-1, _buffer.length
                        - (_fullscreen ? _nrLinesAtFullscreen : _nrLinesAtHalf)));
                    _bufferMeshNeedsUpdate = true;
                    break;

                case GLFW_KEY_PAGEDOWN:
                    _bufferOffset = cast(ushort) max(_bufferOffset - 4, 0);
                    _bufferMeshNeedsUpdate = true;
                    break;

                case GLFW_KEY_TAB:
                    if (!_inCurrentCompletion)
                        _performAutoComplete();
                    else
                    {
                        _input = _currentCompletions[_currentCompletionIndex++].name ~ " ";
                        _cursor = cast(int) _input.length;
                        _currentCompletionIndex %= _currentCompletions.length;
                        _updateInputMesh();
                    }
                    _cursorFlashCounter = 0;
                    break;

                case GLFW_KEY_UP:
                    if (_historyBackPointer < _historyBuffer.length)
                    {
                        ++_historyBackPointer;
                        int historyIndex = _historyBuffer.head - _historyBackPointer;
                        if (historyIndex < 0)
                            historyIndex += _historyBuffer.buffer.length;

                        _input = _historyBuffer.buffer[historyIndex];
                        _cursor = cast(int) _input.length;
                        _updateInputMesh();
                        _inCurrentCompletion = false;
                    }
                    break;

                case GLFW_KEY_DOWN:
                    if (_historyBackPointer > 0)
                    {
                        --_historyBackPointer;

                        if (_historyBackPointer == 0)
                            _input = "";
                        else
                        {
                            int historyIndex = _historyBuffer.head - _historyBackPointer;
                            if (historyIndex < 0)
                                historyIndex += _historyBuffer.buffer.length;

                            _input = _historyBuffer.buffer[historyIndex];
                        }

                        _cursor = cast(int) _input.length;
                        _updateInputMesh();
                        _inCurrentCompletion = false;
                    }
                    break;

                default:
                    break;
            }
        }
        catch (Exception ex) {}
    }

    void _charCallback(uint codepoint) nothrow
    {
        try
        {
            immutable char c = cast(char) codepoint;

            if (c >= ' ' && c <= '~')
            {
                _input = _input[0 .. _cursor] ~ c ~ _input[_cursor .. $];
                _cursor++;

                // Adjust input offset, in case the cursor position got changed.
                while (_cursor >= _inputOffset + _inputMaxLength)
                    ++_inputOffset;
                
                while (_cursor < _inputOffset)
                    --_inputOffset;

                _cursorFlashCounter = 0;

                _updateInputMesh();
                _inCurrentCompletion = false;
            }
        }
        catch (Exception ex) {}
    }

private static:
    int _nrLinesAtHalf;
    int _nrLinesAtFullscreen;
    enum _historyMaxLength = 5;
    int _inputMaxLength;
    int _lineMaxLength;

    struct RingBuffer
    {
        int head;
        int length;
        string[20] buffer = "";
    }

    enum CompletionType
    {
        command,
        variable,
        action,
        useralias
    }

    alias completion_t = Tuple!(string, "name", CompletionType, "type");

    Sprite _background;
    ShaderProgram _shader;
    Font _font;
    mat4 _projectionMatrix;
    mat4 _viewMatrix;

    Mesh _notifyLinesMesh;
    Mesh _bufferMesh;
    Mesh _inputMesh;
    Mesh _cursorMesh;

    bool _bufferMeshNeedsUpdate;
    bool _notifyLinesMeshNeedsUpdate;

    int _position;

    bool _visible = true;
    bool _fullscreen = true;

    ushort _bufferOffset;
    dstring[200] _buffer = "";
    size_t _bufferSize;

    completion_t[] _currentCompletions;
    size_t _currentCompletionIndex;
    bool _inCurrentCompletion;

    RingBuffer _historyBuffer;
    int _historyBackPointer;

    string _input;
    int _inputOffset;
    int _cursor;
    int _charWidth;
    ubyte _cursorFlashCounter;

    alias NotifyLine = Tuple!(dstring, "text", size_t, "time");
    NotifyLine[] _notifyLines;
    
    QVAR.int_t _notifyLinesNr = 4;
    QVAR.int_t _notifyLinesTime = 300;
    QVAR.int_t _showSpeed = 25;

    void _performAutoComplete()
    {
        // If input length is 0, abort
        if (_input.length == 0)
            return;

        // If input string contains a space, abort
        foreach (char c; _input)
            if (c == ' ')
                return;

        _currentCompletions.length = 0;

        if (_input[0] == '+' || _input[0] == '-')
        {
            foreach (string name; Qomproc.actions.keys)
                if (name.startsWith(_input[1..$]))
                    _currentCompletions ~= completion_t(_input[0] ~ name, CompletionType.action);
        }
        else
        {
            // Find completions
            foreach (string name; Qomproc.qcmds.keys)
                if (name.startsWith(_input))
                    _currentCompletions ~= completion_t(name, CompletionType.command);

            foreach (string name; Qomproc.qvars.keys)
                if (name.startsWith(_input))
                    _currentCompletions ~= completion_t(name, CompletionType.variable);

            foreach (string name; Qomproc.aliases.keys)
                if (name.startsWith(_input))
                    _currentCompletions ~= completion_t(name, CompletionType.useralias);
        }

        if (_currentCompletions.length == 1)
        {
            _input = _currentCompletions[0].name ~ " ";
            _cursor = cast(int) _input.length;
            _updateInputMesh();
        }
        else if (_currentCompletions.length > 1)
        {
            Qomproc.println("");

            foreach (ref completion_t completion; _currentCompletions)
                Qomproc.printfln("    %s (%s)", completion.name, completion.type);

            // Check how many characters are the same
            size_t length;
        outerLoop:
            while (true)
            {
                if (_currentCompletions[0].name.length <= length)
                    break;
                
                immutable char c = _currentCompletions[0].name[length];
                foreach (ref completion_t completion; _currentCompletions)
                    if (completion.name.length <= length || completion.name[length] != c)
                        break outerLoop;
                ++length;
            }

            if (length > 0)
            {
                _input = _currentCompletions[0].name[0..length];
                _cursor = cast(int) _input.length;
                _updateInputMesh();
            }

            _inCurrentCompletion = true;
            _currentCompletionIndex = 0;
        }
    }

    void _updateBufferMesh()
    {
        dstring bufferText = "";
        immutable int nrOfLines = (_fullscreen ? _nrLinesAtFullscreen : _nrLinesAtHalf)
            - (_bufferOffset == 0 ? 0 : 1);
        for (int i = nrOfLines-1; i >= 0; --i)
            bufferText ~= _buffer[_bufferOffset + i] ~ "\n";

        if (_bufferOffset != 0)
            bufferText ~= "     ^      ^      ^      ^      ^      ^      ^      ^      ^      ^      ^      ^";

        scope Vertex[] vertices;
        scope uint[] indices;
        if (bufferText.length > 0)
            GraphicsServer.getTextVertices(bufferText, _font, vertices, indices);
        _bufferMesh.updateData(vertices, indices);
    }

    void _updateNotifyLinesMesh()
    {
        dstring notifyLinesText = "";
        for (size_t i; i < _notifyLines.length; ++i)
            notifyLinesText ~= _notifyLines[i].text ~ "\n";

        scope Vertex[] vertices;
        scope uint[] indices;
        if (notifyLinesText.length > 0)
            GraphicsServer.getTextVertices(notifyLinesText, _font, vertices, indices);
        _notifyLinesMesh.updateData(vertices, indices);
    }

    void _updateInputMesh()
    {
        scope Vertex[] vertices;
        scope uint[] indices;
        GraphicsServer.getTextVertices("> " ~ _input[_inputOffset .. min(_input.length,
            _inputOffset + _inputMaxLength)], _font, vertices, indices);
        _inputMesh.updateData(vertices, indices);
    }
}

class QomprocOutputGUI : IQomprocOutput
{
public:
    void print(string message) nothrow @trusted
    {
        try
        {
            foreach (string line; message.splitLines)
            {
                if (line.length == 0)
                    appendBuffer("");
                else
                    foreach (string chunk;
                        line.chunks(QomprocGUI._lineMaxLength > 0 ? QomprocGUI._lineMaxLength : size_t.max)
                        .map!(x => x.to!string))
                        appendBuffer(chunk.to!dstring);
            }
        }
        catch (Exception) {}
    }

private:
    void appendBuffer(dstring text) @trusted
    {
        with (QomprocGUI)
        {
            for (size_t i = _buffer.length - 1; i > 0; --i) // @suppress(dscanner.suspicious.length_subtraction)
                _buffer[i] = _buffer[i - 1];

            _buffer[0] = text.idup;
            if (_bufferSize < _buffer.length)
                _bufferSize++;

            if (!_visible)
            {
                if (_notifyLines.length == _notifyLinesNr)
                    _notifyLines = _notifyLines[1 .. $];
                
                _notifyLines ~= NotifyLine(text.idup, _notifyLinesTime);
                _notifyLinesMeshNeedsUpdate = true;
            }
            else
                _bufferMeshNeedsUpdate = true;
        }
    }
}