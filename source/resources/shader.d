module qrescent.resources.shader;

import std.conv : to;
import std.exception : enforce, collectException;
import std.string : toStringz;

import sdlang;
import derelict.opengl;
import gl3n.linalg;

import qrescent.core.servers.language : tr;
import qrescent.core.exceptions;
import qrescent.core.vfs;
import qrescent.core.engine;
import qrescent.core.qomproc;
import qrescent.resources.loader;

/**
Represents an OpenGL Shader Program.
A ShaderProgram is compiled of many different `Shader`s, but usually
only out of the vertex and fragment shader.
*/
final class ShaderProgram : Resource
{
public:
    ~this() nothrow @trusted @nogc
    {
        if (_program > 0)
            glDeleteProgram(_program);
    }
	
    /**
    Attaches one or more shaders to this program.

    Params:
        shaders = The shaders to attach.
    */
    void attachShader(Shader[] shaders...) nothrow @safe
    {
        _attachedShaders ~= shaders;
    }
	
    /**
    Links and validates the ShaderProgram with all attached shaders.
    On success, it deattaches all previously attached shaders.
    
    Throws: `GraphicsException` if allocation fails, when a Shader is not compiled or
            when linking and/or validation fails.
    */
    void link() @trusted
    {
        scope (success) _attachedShaders.length = 0; // Free all attached Shaders on exit
        scope (failure) if (_program > 0) glDeleteProgram(_program);
    	
        _program = glCreateProgram();
        enforce!GraphicsException(_program > 0, "Failed to allocate a new Shader Program.".tr);
    	
        foreach (Shader shader; _attachedShaders)
        {
            enforce!GraphicsException(shader._shader > 0, "Cannot add uncompiled Shader.".tr);
        	
            glAttachShader(_program, shader._shader);
        }
    	
        int isLinked;
        int isValidated = GL_FALSE; // Default to GL_FALSE since validation is optional (see below)
    	
        glLinkProgram(_program);
        glGetProgramiv(_program, GL_LINK_STATUS, &isLinked);
    	
        if (isLinked == GL_TRUE) // Only validate if linking was successful.
        {
            glValidateProgram(_program);
            glGetProgramiv(_program, GL_VALIDATE_STATUS, &isValidated);
        }
    	
        // Retrieve log
        int logLength;
        glGetProgramiv(_program, GL_INFO_LOG_LENGTH, &logLength);
    	
        char[] log = new char[logLength];
        glGetProgramInfoLog(_program, logLength, &logLength, log.ptr);
    	
        if (isLinked == GL_FALSE || isValidated == GL_FALSE)
            throw new GraphicsException(log.idup);
        else if (logLength > 0)
            Qomproc.println(log.idup);
    }
	
    /**
    Binds this ShaderProgram for future use.
    */
    void bind() nothrow @trusted @nogc
    {
        glUseProgram(_program);
    }
	
    /**
    Unbinds a currently bound ShaderProgram.
    */
    static void unbind() nothrow @trusted @nogc
    {
        glUseProgram(0);
    }
	
    /**
    Gets the location of the uniform with the given name.
    The location will be cached, so subsequent calls will be faster.

    Params:
        uniform = The name of the uniform.

    Returns: The location of the uniform, or -1 if not found.
    */
    int getUniformLocation(string uniform) nothrow @trusted
    {
        // Check cache
        if (int* cacheLoc = uniform in _uniforms)
            return *cacheLoc;
        else
            return _uniforms[uniform] = glGetUniformLocation(_program, uniform.toStringz);
    }

    /**
    Sets the uniform of the given name to the given value.
    The location will be cached, so subsequent calls will be faster.
    In case the ShaderProgram is not bound yet, this method will do
    this automatically.

    Params:
        uniform = The name of the uniform.
        value = The value to set the uniform to.

    Throws: `GraphicsException` if the program is unlinked.
    */
    void setUniform(T)(string uniform, T value) @trusted
    {
        enforce!GraphicsException(_program > 0, "Cannot set uniform of an unlinked Shader Program.".tr);
    	
        setUniform(getUniformLocation(uniform), value);
    }
	
    /**
    Sets the uniform at the given location to the given value.
    In case the ShaderProgram is not bound yet, this method will do
    this automatically.

    Params:
        location = The location of the uniform. If the location is invalid,
                   this method does nothing.
        value = The value to set the uniform to.

    Throws: `GraphicsException` if the program is unlinked.
    */
    void setUniform(T)(int location, T value) @trusted
    {
        if (location < 0)
            return;

        enforce!GraphicsException(_program > 0, "Cannot set uniform of an unlinked Shader Program.".tr);
    	
        bind();
    	
        static if (is(T == uint))
            glUniform1ui(location, value);
        else static if (is(T == int))
            glUniform1i(location, value);
        else static if(is(T == uint))
            glUniform1u(location, value);
        else static if (is(T == float))
            glUniform1f(location, value);
        else static if (is(T == vec2))
            glUniform2f(location, value.x, value.y);
        else static if (is(T == vec3))
            glUniform3f(location, value.x, value.y, value.z);
        else static if (is(T == vec4))
            glUniform4f(location, value.x, value.y, value.z, value.w);
        else static if (is(T == mat4))
            glUniformMatrix4fv(location, 1, true, value.value_ptr);
        else
            static assert(false, "Value of type " ~ T.stringof ~ " cannot be assigned to an uniform.");
    }

    /// The internal OpenGL id of this shader program.
    @property uint program() const pure nothrow { return _program; } // @suppress(dscanner.style.doc_missing_returns)
	
private:
    uint _program;
    Shader[] _attachedShaders; // Only used for linking; freed afterwards.
	
    int[string] _uniforms; // Cached Shader Program uniform locations.
}

/**
Represents an individual OpenGL Shader.
To use it in a ShaderProgram, it needs to be compiled first.
*/
final class Shader
{
public:
    /// The type of a shader.
    enum Type : int
    {
        vertex = GL_VERTEX_SHADER, /// Vertex shader (required)
        geometry = GL_GEOMETRY_SHADER, /// Geometry shader
        fragment = GL_FRAGMENT_SHADER, /// Fragment shader (required)
        compute = GL_COMPUTE_SHADER, /// Compute shader
        tessControl = GL_TESS_CONTROL_SHADER, /// Tess control shader
        tessEvaluation = GL_TESS_EVALUATION_SHADER /// Tess evaluation shader
    }
	
    /**
    Constructs a new shader.

    Params:
        type = The type of the shader.
    */
    this(Type type) nothrow @safe @nogc
    {
        _type = type;
    }
	
    ~this() nothrow @trusted @nogc
    {
        if (_shader > 0)
            glDeleteShader(_shader);
    }
	
    /**
    Compiles this shader with the given source.

    Params:
        source = The shader source code.

    Throws: `GraphicsException` if allocation or compilation fails.
    */
    void compile(string source) @trusted
    {
        scope (failure) if (_shader > 0) glDeleteShader(_shader);
    	
        _shader = glCreateShader(cast(int) _type);
        enforce!GraphicsException(_shader > 0, "Failed to allocate a new Shader.".tr);
    	
        auto ptr = cast(const char*) source.ptr;
        int ptrLength = cast(int) source.length;
    	
        glShaderSource(_shader, 1, &ptr, &ptrLength);
        glCompileShader(_shader);
    	
        // Check if the Shader got compiled
        int isCompiled;
        glGetShaderiv(_shader, GL_COMPILE_STATUS, &isCompiled);
    	
        // Retrieve log
        int logLength;
        glGetShaderiv(_shader, GL_INFO_LOG_LENGTH, &logLength);
    	
        char[] log = new char[logLength];
        glGetShaderInfoLog(_shader, logLength, &logLength, log.ptr);
    	
        // If the Shader failed to compile, throw the log as an Exception. Otherwise, if log output exists, print it
        // as a warning to Qomproc.
        if (isCompiled == GL_FALSE)
            throw new GraphicsException(log.idup);
        else if (logLength > 0)
            Qomproc.println(log.idup);
    }
	
    /// The type of this Shader.
    @property Type type() const pure nothrow @safe @nogc { return _type; } // @suppress(dscanner.style.doc_missing_returns)
	
private:
    uint _shader;
    Type _type;
}

// ===== SHADER LOADER FUNCTION =====

package:

Resource resLoadShaderProgram(string path)
{
    Tag root;
    ShaderProgram program = new ShaderProgram();

    { // Parse definition file
        scope IVFSFile file;
        if (Exception ex = collectException(VFS.getFile(path), file))
        {
            Qomproc.printfln("Failed to load shader '%s': %s".tr, path, ex.msg);
            file = VFS.getFile(EngineCore.projectSettings.fallbackMesh);
        }
        char[] shaderDefSource = new char[file.size];
        file.read(shaderDefSource);

        root = parseSource(cast(string) shaderDefSource, path);
    }

    void loadShader(Shader.Type type)
    {
        char[] source;

        // Look for the tag that defines this shader
        string tagName = type.to!string;
        Tag shaderTag = root.getTag(tagName);
        if (!shaderTag)
            return;

        // Check if it references another file
        string fileName = shaderTag.getAttribute!string("file", null);
        if (fileName)
        {
            scope IVFSFile shaderFile = VFS.getFile(fileName);
            source = new char[shaderFile.size];
            shaderFile.read(source);
        }
        else
            source = cast(char[]) shaderTag.expectValue!string;

        Shader shader = new Shader(type);
        shader.compile(cast(string) source);

        program.attachShader(shader);
    }

    loadShader(Shader.Type.vertex);
    loadShader(Shader.Type.fragment);
    loadShader(Shader.Type.geometry);
    loadShader(Shader.Type.compute);
    loadShader(Shader.Type.tessControl);
    loadShader(Shader.Type.tessEvaluation);

    program.link();

    return program;
}