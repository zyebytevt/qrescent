module qrescent.components.text;

import gl3n.linalg;
import sdlang;

import qrescent.ecs;
import qrescent.ecs.utils;
import qrescent.resources.loader;
import qrescent.resources.font;
import qrescent.resources.mesh;
import qrescent.resources.shader;
import qrescent.core.engine;
import qrescent.core.servers.graphics;

/**
The TextComponent, if attached, will render some text with the given
font with the current entity's transform.
*/
@component struct TextComponent
{
public:
    ShaderProgram shader; /// The shader used for rendering.

    ~this()
    {
        _mesh.destroy();
    }

    /// The text that will be rendered.
    @property dstring text() @safe const nothrow { return _text; } // @suppress(dscanner.style.doc_missing_returns)
    /// ditto
    @property void text(dstring value) @safe // @suppress(dscanner.style.doc_missing_params)
    {
        _text = value;
        _updateMesh();
    }

    /// The font used for text rendering.
    @property Font font() @safe nothrow { return _font; } // @suppress(dscanner.style.doc_missing_returns)
    /// ditto
    @property void font(Font value) @safe // @suppress(dscanner.style.doc_missing_params)
    {
        _font = value;
        _updateMesh();
    }

    /// The alignment of the text.
    @property Font.Alignment alignment() @safe nothrow { return _alignment; } // @suppress(dscanner.style.doc_missing_returns)
    /// ditto
    @property void alignment(Font.Alignment value) @safe // @suppress(dscanner.style.doc_missing_params)
    {
        _alignment = value;
        _updateMesh();
    }

    /// The mesh that contains the text, ready for rendering.
    @property Mesh mesh() @safe nothrow { return _mesh; } // @suppress(dscanner.style.doc_missing_returns)

    /**
	Registers this component to the given entity, with values from a SDLang tag.

	Params:
		root = The root SDLang tag that describes this component.
		entity = The entity to register this component to.
		isOverride = `true` if overriding attributes of an already existing component,
		`false` otherwise.
	*/
	static void loadFromTag(Tag root, Entity entity, bool isOverride)
	{
        TextComponent* component = entity.getComponent!TextComponent(isOverride);

        // Private enums used for scene loading
        enum Vertical : uint
        {
            top = Font.Alignment.top,
            middle = Font.Alignment.middle,
            bottom = Font.Alignment.bottom
        }

        enum Horizontal : uint
        {
            left = Font.Alignment.left,
            center = Font.Alignment.center,
            right = Font.Alignment.right
        }

        Vertical vertical;
        Horizontal horizontal;

        setAttribute(root, "font", &component._font, isOverride);
        setAttribute(root, "shader", &component.shader, isOverride);
        setAttribute(root, "text", &component._text, isOverride);
        setAttribute(root, "align-horizontal", &horizontal, isOverride);
        setAttribute(root, "align-vertical", &vertical, isOverride);

        component._alignment = cast(Font.Alignment) (vertical | horizontal);
        component._updateMesh();
	}

private:
    dstring _text;
    Font _font;
    Mesh _mesh;
    Font.Alignment _alignment;

    void _updateMesh() @trusted
    {
        scope Vertex[] vertices;
        scope uint[] indices;

        if (_text && _font)
            GraphicsServer.getTextVertices(_text, _font, vertices, indices, _alignment);
        
        if (!_mesh)
            _mesh = new Mesh(vertices, indices, Mesh.DrawMethod.dynamic);
        else
            _mesh.updateData(vertices, indices);
    }
}