module qrescent.resources.mesh;

import std.string : splitLines, strip, startsWith, split;
import std.conv : to;
import std.exception : collectException;

import derelict.opengl;
import gl3n.linalg;
import gl3n.util;

import qrescent.core.servers.language : tr;
import qrescent.core.engine;
import qrescent.core.qomproc;
import qrescent.core.vfs;
import qrescent.resources.loader;

/**
Holds data for a vertex in a mesh.
*/
struct Vertex
{
	vec3 position; /// The local position of the vertex.
	vec2 texCoords; /// The texture coordinates (u,v) of the vertex.
	vec3 normal; /// The normal vector of the vertex.
	vec4 color = vec4(1, 1, 1, 1); /// The color of the vertex.
}

/**
Represents a basic mesh.
*/
class Mesh : Resource
{
public:
    /// How to store the mesh in VRAM.
	enum DrawMethod : GLenum
	{
		static_ = GL_STATIC_DRAW, /// Mesh will be modified once and used many times.
		dynamic = GL_DYNAMIC_DRAW, /// Mesh will be modified repeatedly and used many times.
        stream = GL_STREAM_DRAW // Mesh will be modified once and used at most a few times.
	}

	/**
    Construct a new mesh.

    Params:
        vertices = The vertices to use.
        indices = The indices to use.
        drawMethod = How to store the mesh in VRAM.
    */
	this(Vertex[] vertices, uint[] indices, DrawMethod drawMethod = DrawMethod.static_) nothrow @trusted
	{
		glGenVertexArrays(1, &_vaoID);
		glBindVertexArray(_vaoID);

		// Vertex and Index VBO
		glGenBuffers(2, _vboIDs.ptr);

		// Setup Vertex VBO
		glBindBuffer(GL_ARRAY_BUFFER, _vboIDs[0]);
		glBufferData(GL_ARRAY_BUFFER, vertices.length * Vertex.sizeof, vertices.ptr, drawMethod);

		static foreach(i, member; __traits(allMembers, Vertex))
		{
			static assert(is_vector!(typeof(__traits(getMember, Vertex, member))),
				"Vertex can only contain vectors!");

			glEnableVertexAttribArray(i);
			glVertexAttribPointer(i,
				mixin("Vertex." ~ member ~ ".sizeof") / float.sizeof,
				GL_FLOAT,
				false,
				Vertex.sizeof,
				cast(void*)(mixin("Vertex." ~ member ~ ".offsetof"))
				);
		}

		// Setup Index VBO
		glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, _vboIDs[1]);
		glBufferData(GL_ELEMENT_ARRAY_BUFFER, indices.length * uint.sizeof, indices.ptr, drawMethod);

		glBindVertexArray(0);
		
		_vertexCount = cast(uint) indices.length;
	}
	
	~this() nothrow @trusted
	{
		glDeleteVertexArrays(1, &_vaoID);
		glDeleteBuffers(2, _vboIDs.ptr);
	}

    /**
    Updates the data of this mesh.

    Params:
        vertices = The new vertices to update to.
        indices = The new indices to update to.
        drawMethod = How to store the mesh in VRAM.
    */
    void updateData(Vertex[] vertices, uint[] indices, DrawMethod drawMethod = DrawMethod.dynamic) nothrow @trusted
    {
        glBindVertexArray(_vaoID);
        _vertexCount = cast(uint) indices.length;

        glBindBuffer(GL_ARRAY_BUFFER, _vboIDs[0]);
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, _vboIDs[1]);

        glBufferData(GL_ARRAY_BUFFER, vertices.length * Vertex.sizeof, vertices.ptr, drawMethod);
        glBufferData(GL_ELEMENT_ARRAY_BUFFER, indices.length * uint.sizeof, indices.ptr, drawMethod);

        glBindVertexArray(0);
    }

    /**
    Draws this mesh.
    $(RED Make sure the mesh is bound first!)
    */
    void draw() const nothrow @trusted
    {
        glDrawElements(GL_TRIANGLES, _vertexCount, GL_UNSIGNED_INT, cast(void*) 0);
    }
	
	/**
    Binds this mesh for future use.
    */
	void bind() const nothrow @trusted
	{
		glBindVertexArray(_vaoID);
		glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, _vboIDs[1]);
	}
	
	/**
    Unbinds a currently bound mesh.
    */
	static void unbind() nothrow @trusted
	{
		glBindVertexArray(0);
		glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);
	}

	/// The amount of vertices this mesh has.
	@property uint vertexCount() const nothrow @safe { return _vertexCount; } // @suppress(dscanner.style.doc_missing_returns)
	
private:
	uint _vaoID;
	uint[2] _vboIDs;
	uint _vertexCount;
}

// ===== OBJ LOADER FUNCTION =====

package:

Resource resLoadOBJMesh(string path)
{
    string contents;
    { // Parse definition file
        scope IVFSFile file;
        
        if (Exception ex = collectException(VFS.getFile(path), file))
        {
            Qomproc.printfln("Failed to load mesh '%s': %s".tr, path, ex.msg);
            file = VFS.getFile(EngineCore.projectSettings.fallbackMesh);
        }
        char[] source = new char[file.size];
        file.read(source);

        contents = cast(string) source;
    }

    vec4[] positions;
    vec2[] uvs;
    vec3[] normals;

    Vertex[] vertices;
    uint[] indices;

    size_t[size_t] positionToVertexIndex;

    foreach (string line; contents.splitLines)
    {
        line = line.strip();

        if (line.startsWith("#") || line.length == 0) // comment or blank line
            continue;

        string[] command = line.split();

        switch (command[0])
        {
            case "v": // Vertex position
                immutable float x = command[1].to!float;
                immutable float y = command[2].to!float;
                immutable float z = command[3].to!float;
                float w = 1.0f;

                if (command.length > 4)
                    w = command[4].to!float;

                positions ~= vec4(x, y, z, w);
                break;

            case "vt": // Texture coordinate
                immutable float u = command[1].to!float;
                float v = 0f;

                if (command.length > 2)
                    v = command[2].to!float;

                uvs ~= vec2(u, v);
                break;

            case "vn": // Vertex normal
                immutable float x = command[1].to!float;
                immutable float y = command[2].to!float;
                immutable float z = command[3].to!float;

                normals ~= vec3(x, y, z);
                break;

            case "f": // Faces
                foreach (string vertexDef; command[1..$])
                {
                    size_t positionIdx;
                    size_t texCoordsIdx;
                    size_t normalsIdx;
                    
                    {
                        auto vertexDefAttribs = vertexDef.split("/");

                        if (vertexDefAttribs.length >= 1 && vertexDefAttribs[0] != "")
                            positionIdx = vertexDefAttribs[0].to!size_t;

                        if (vertexDefAttribs.length >= 2 && vertexDefAttribs[1] != "")
                            texCoordsIdx = vertexDefAttribs[1].to!size_t;

                        if (vertexDefAttribs.length >= 3 && vertexDefAttribs[2] != "")
                            normalsIdx = vertexDefAttribs[2].to!size_t;
                    }
                    
                    // Check if the position was already processed earlier
                    size_t* vertexIndex = positionIdx in positionToVertexIndex;

                    // If so, add the index to the indices.
                    if (vertexIndex)
                        indices ~= cast(uint) *vertexIndex;
                    else // Otherwise, build new vertex and write into positionToVertexIndex.
                    {
                        Vertex v;
                        
                        v.position = positions[positionIdx-1].xyz;

                        if (texCoordsIdx > 0)
                            v.texCoords = uvs[texCoordsIdx-1];

                        if (normalsIdx > 0)
                            v.normal = normals[normalsIdx-1];

                        positionToVertexIndex[positionIdx] = vertices.length;
                        indices ~= cast(uint) vertices.length;
                        vertices ~= v;
                    }
                }
                break;

            default:
                break;
        }
    }

    return new Mesh(vertices, indices);
}