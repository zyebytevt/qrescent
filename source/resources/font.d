module qrescent.resources.font;

import std.traits : isSomeString;
import std.exception : enforce, collectException;
import std.range.primitives : ElementType;
import std.conv : to;

import imageformats;

import qrescent.core.servers.language : tr;
import qrescent.core.engine;
import qrescent.core.vfs;
import qrescent.core.qomproc;
import qrescent.resources.loader;
import qrescent.resources.texture;

/**
Represents a font, which is used to give text a distinct look
and feel.
*/
class Font : Resource
{
public:
    /// Data of a single character of a font.
    struct Character
    {
        int x; /// X position in the texture map, in pixels.
        int y; /// Y position in the texture map, in pixels.
        int width; /// Width in the texture map, in pixels.
        int height; /// Height in the texture map, in pixels.
        int xoffset; /// Amount of pixels in X that the glyph should be offset.
        int yoffset; /// Amount of pixels in Y that the glyph should be offset.
        int xadvance; /// Amount of pixels to advance.
        int page; /// Index of the texture where this glyph is contained.
    }

    /// Common data of the font.
    struct Common
    {
        int lineHeight;
        int base;
    }

    /// Kerning data.
    struct Kerning
    {
        int first;
        int second;
        int amount;
    }

    /// How a text should be aligned.
    enum Alignment : uint
    {
        top = 1,
        middle = 1 << 1,
        bottom = 1 << 2,

        left = 1 << 3,
        center = 1 << 4,
        right = 1 << 5
    }

    Common common; /// Common data of the font.
    Texture2D[] pages; /// All pages of the font, represented as Texture2D's.
    Character[int] characters; /// Data of all characters of this font.
    Kerning[] kernings; /// Kerning data.

    /**
    Gets the width of the given string in this font, in pixels.

    Params:
        text = The text to get the width of.

    Returns: The width of the text in this font, in pixels.
    */
    int getTextWidth(T)(T text)
        if (isSomeString!T)
    {
        int maxLength, lineLength;

        for (size_t i; i < text.length; ++i)
        {
            immutable ElementType!T c = text[i];

            if (c == '\n')
            {
                lineLength = 0;
                continue;
            }

            int kerning = 1;
            if (i > 0)
            {
                foreach (ref Kerning k; kernings)
                    if (k.first == text[i-1] && k.second == text[i])
                        kerning = k.amount;
            }

            if (c in characters)
                lineLength += characters[c].xadvance + kerning;
            
            if (lineLength > maxLength)
                maxLength = lineLength;
        }

        return maxLength;
    }

    /**
    Gets the height of the given string in this font, in pixels.

    Params:
        text = The text to get the height of.

    Returns: The height of the text in this font, in pixels.
    */
    int getTextHeight(T)(T text)
        if (isSomeString!T)
    {
        int lines = 1;

        foreach (c; text)
        {
            if (c == '\n')
                ++lines;
        }

        return common.lineHeight * lines;
    }
}

// ===== FONT LOADER FUNCTION =====

package:

Resource resLoadFont(string path)
{
    // Load source
    scope IVFSFile fontFile;
    {
        if (Exception ex = collectException(VFS.getFile(path), fontFile))
        {
            Qomproc.printfln("Failed to load font '%s': %s".tr, path, ex.msg);
            fontFile = VFS.getFile(EngineCore.projectSettings.fallbackFont);
        }
    }

    char[4] magic;
    fontFile.read(magic.ptr, char.sizeof, 4);
    enforce(magic == "QFF1", "Font must be in QFF1 format.".tr);

    Font font = new Font();

    // Read common data
    font.common.lineHeight = fontFile.readNumber!int;
    font.common.base = fontFile.readNumber!int;

    // Read kerning data
    uint count = fontFile.readNumber!uint;
    for (uint i; i < count; ++i)
    {
        Font.Kerning kerning;

        kerning.first = fontFile.readNumber!int;
        kerning.second = fontFile.readNumber!int;
        kerning.amount = fontFile.readNumber!int;

        font.kernings ~= kerning;
    }

    // Read characters
    count = fontFile.readNumber!uint;
    for (uint i; i < count; ++i)
    {
        Font.Character character;
        immutable int idx = fontFile.readNumber!int;

        character.x = fontFile.readNumber!int;
        character.y = fontFile.readNumber!int;
        character.width = fontFile.readNumber!int;
        character.height = fontFile.readNumber!int;
        character.xoffset = fontFile.readNumber!int;
        character.yoffset = fontFile.readNumber!int;
        character.xadvance = fontFile.readNumber!int;
        character.page = fontFile.readNumber!int;

        font.characters[idx] = character;
    }

    // Read pages
    count = fontFile.readNumber!uint;
    for (uint i; i < count; ++i)
    {
        ubyte[] imgBuffer = new ubyte[fontFile.readNumber!uint];
        fontFile.read(imgBuffer);

        font.pages ~= new Texture2D(read_image_from_mem(imgBuffer));
    }

    return font;
}