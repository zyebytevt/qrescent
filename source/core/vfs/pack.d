module qrescent.core.vfs.pack;

import std.exception : enforce;
import std.string : empty, format, toStringz, endsWith;
import std.file : exists, isFile;
import std.path : dirSeparator;
import core.stdc.stdio;

import qrescent.core.servers.language : tr;
import qrescent.core.exceptions;
import qrescent.core.vfs;

/**
Represents a package inside the Qrescent VFS.
*/
interface IVFSPackage
{
	/**
	Retrieves the specified file from this package.
	
	Params:
		path = The path inside this package.
		mode = The mode by which the file should be opened.
	
	Returns: The retrieved file.
	Throws: `VFSException` if the file cannot be found.
	*/
	IVFSFile getFile(string path, string mode = "r");

	/**
	Checks if the specified file exists.
	
	Params:
		path = The path inside this package.

	Returns: If the given file exists.
	*/
	bool hasFile(string path) nothrow;

	/// The location of this package in the real filesystem
	@property string location() nothrow;
	/// The VFS registered name of this package.
	@property string name() nothrow;
}

package:

class VFSDirectoryPackage : IVFSPackage
{
public:
	IVFSFile getFile(string path, string mode = "r") 
	{
		enforce!VFSException(!path.empty, "Path cannot be empty.".tr);
		enforce!VFSException(!(path.length > 1 && path[0] == '/'), "Paths cannot start with an '/'.".tr);

		FILE* f = fopen((_location ~ path).toStringz, mode.toStringz);
		enforce!VFSException(f, "File '%s://%s' does not exist.".tr.format(_name, path));

		return new VFSRealFile(this, path, f);
	}

	bool hasFile(string path) nothrow
	{
		try { return exists(_location ~ path) && isFile(_location ~ path); }
		catch (Exception) { return false; }
	}

	@property string location() nothrow { return _location; }
	@property string name() nothrow { return _name; }

package:
	string _name, _location;

	this(string name, string location)
	{
		if (!location.endsWith(dirSeparator))
			location ~= dirSeparator;

		_name = name;
		_location = location;
	}
}


class VFSQPKPackage : IVFSPackage
{
public:
	~this()
	{
		fclose(_archiveFile);
	}

	IVFSFile getFile(string path, string mode) // @suppress(dscanner.suspicious.unused_parameter)
	{
		enforce!VFSException(!path.empty, "Path cannot be empty.".tr);
		enforce!VFSException(!(path.length > 1 && path[0] == '/'), "Paths cannot start with an '/'.".tr);

		FileInfo* fileInfo = path in _files;
		enforce!VFSException(fileInfo, "File '%s://%s' does not exist.".tr.format(_name, path));

		return new VFSQPKFile(this, path, _archiveFile, fileInfo.offset, fileInfo.size);
	}

	bool hasFile(string path) nothrow
	{
		return (path in _files) !is null;
	}

	@property string location() nothrow { return _location; }
	@property string name() nothrow { return _name; }

package:
	struct FileInfo
	{
		uint offset;
		uint size;
	}

	string _name, _location;
	FileInfo[string] _files;
	FILE* _archiveFile;

	this(string name, string location)
	{
		_name = name;
		_location = location;
		
		_archiveFile = fopen(location.toStringz, "rb");
		enforce!VFSException(_archiveFile, "Failed to open package file '%s'.".tr.format(location));

		// Check magic number
		char[4] magic;
		fread(magic.ptr, 4, char.sizeof, _archiveFile);
		enforce!VFSException(magic == "QPK1", "Invalid package file.".tr);

		// Go to central directory
		immutable uint centralDirectoryOffset = _archiveFile.readPrimitive!uint;
		fseek(_archiveFile, centralDirectoryOffset, SEEK_SET);

		// Read central directory
		immutable uint fileAmount = _archiveFile.readPrimitive!uint;
		for (size_t i; i < fileAmount; ++i)
			_files[_archiveFile.readPString] = FileInfo(_archiveFile.readPrimitive!uint, _archiveFile.readPrimitive!uint);
	}
}

private:

string readPString(LengthType = ushort)(FILE* file)
{
	import std.bitmanip : read, Endian;

	LengthType length = file.readPrimitive!LengthType;
	char[] str = new char[length];

	fread(str.ptr, char.sizeof, length, file);
	return str.idup;
}

T readPrimitive(T)(FILE* file)
{
	import std.bitmanip : read, Endian;

	ubyte[] buffer = new ubyte[T.sizeof];
	fread(buffer.ptr, ubyte.sizeof, T.sizeof, file);

	return read!(T, Endian.littleEndian)(buffer);
}