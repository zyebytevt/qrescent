module qrescent.core.vfs.file;

public import std.bitmanip : Endian;

import std.exception : enforce;
import std.string : fromStringz, format;
import std.bitmanip : bigEndianToNative, littleEndianToNative, nativeToBigEndian, nativeToLittleEndian;
import std.traits : isNumeric, isSomeString, isUnsigned;
import std.range : ElementType;
import core.stdc.stdio;
import core.stdc.string;

import qrescent.core.servers.language : tr;
import qrescent.core.exceptions;
import qrescent.core.vfs;

/**
Represents a file inside the Qrescent VFS.
*/
interface IVFSFile
{
	/// Whence to seek from.
	enum Seek : int
	{
		current = SEEK_CUR, /// Relative to the current position.
		end = SEEK_END, /// Relative to the end of the file.
		set = SEEK_SET /// Set to an absolute value.
	}

	/**
	Reads a chunk from the stream and store it into a variable.
	
	Params:
		ptr = The memory to store the data into.
		size = The size of a single unit in bytes.
		n = The number of units.
	
	Returns: The amount of bytes read.
	*/
	long read(void* ptr, size_t size, size_t n);

	/**
	Reads a chunk from the stream and store it into the buffer.
	
	Params:
		buffer = The buffer to store the data into.
	
	Returns: The number of bytes read.
	*/
	long read(void[] buffer);

	/**
	Writes data from a memory location to the stream.
	
	Params:
		ptr = The memory to read the data from.
		size = The size of a single unit in bytes.
		n = The number of units.
	
	Returns: The amount of bytes written.
	*/
	long write(const void* ptr, size_t size, size_t n);

	/**
	Writes data from a buffer to the stream.
	
	Params:
		buffer = The buffer to read the data from.
	
	Returns: The number of bytes written.
	*/
	long write(const void[] buffer);

	/**
	Changes the stream pointer position.
	
	Params:
		offset = The offset relative to the value of `whence`.
		whence = How to interpret the value of `offset`.
	
	Returns: The new position.
	Throws: `VFSException` if the pointer couldn't be changed.
	*/
	long seek(long offset, Seek whence);

	final T readNumber(T)(Endian endianness = Endian.littleEndian)
		if (isNumeric!T)
	{
		ubyte[T.sizeof] buffer;
		read(buffer.ptr, T.sizeof, 1);
		
		final switch (endianness)
		{
			case Endian.littleEndian:
				return littleEndianToNative!T(buffer);

			case Endian.bigEndian:
				return bigEndianToNative!T(buffer);
		}
	}

	final S readPascalString(S = string, LengthType = ushort)(Endian endianness = Endian.littleEndian)
		if (isSomeString!S && isUnsigned!LengthType)
	{
		alias Char = ElementType!S;

		LengthType length = readNumber!LengthType(endianness);
		Char[] buffer = new Char[length];

		read(buffer.ptr, Char.sizeof, length);
		return buffer.idup;
	}

	final void writeNumber(T)(T number, Endian endianness = Endian.littleEndian)
		if (isNumeric!T)
	{
		ubyte[T.sizeof] buffer;

		final switch (endianness)
		{
			case Endian.littleEndian:
				buffer = nativeToLittleEndian(number);
				break;

			case Endian.bigEndian:
				buffer = nativeToBigEndian(number);
				break;
		}

		write(buffer.ptr, T.sizeof, 1);
	}

	final void writePascalString(S = string, LengthType = ushort)(S text, Endian endianness = Endian.littleEndian)
		if (isSomeString!S && isUnsigned!LengthType)
	{
		alias Char = ElementType!S;

		writeNumber(cast(LengthType) text.length, endianness);
		write(text.ptr, Char.sizeof, text.length);
	}

	/**
	Gets the current stream pointer position.

	Returns: Stream pointer position.
	*/
	long tell() nothrow;

	/// The size of this file in bytes.
	@property long size() nothrow;

	/// The containing package of this file.
	@property IVFSPackage container() nothrow;

	/// The location of this file inside the VFS.
	@property string location() nothrow;
}

package:

class VFSRealFile : IVFSFile
{
public:
	~this()
	{
		fclose(_file);
	}

	long read(void* ptr, size_t size, size_t n)
	{
		return fread(ptr, size, n, _file);
	}

	long read(void[] buffer)
	{
		return read(buffer.ptr, void.sizeof, buffer.length);
	}

	long write(const void* ptr, size_t size, size_t n)
	{
		long bWritten = cast(long) fwrite(ptr, size, n, _file);
		enforce!VFSException(bWritten == n,
			"Failed to write to file (Errno: %d)! Is the correct mode set?".tr.format(ferror(_file)));

		return bWritten;
	}

	long write(const void[] buffer)
	{
		return write(buffer.ptr, void.sizeof, buffer.length);
	}

	long seek(long offset, IVFSFile.Seek whence)
	{
		long result = cast(long) fseek(_file, offset, cast(int) whence);

		import std.string : fromStringz;
		
		enforce!VFSException(result == 0, "VFSRealFile: Failed to seek (%s)".tr.format(strerror(cast(int) result).fromStringz));

		return offset;
	}

	long tell() nothrow
	{
		return ftell(_file);
	}

	@property long size() nothrow
	{
		immutable long pos = ftell(_file);
		fseek(_file, 0, SEEK_END);
		immutable long size = ftell(_file);
		fseek(_file, pos, SEEK_SET);

		return size;
	}

	@property IVFSPackage container() nothrow { return _container; }

	@property string location() nothrow { return _container.name ~ "://" ~ _location; }

package:
	IVFSPackage _container;
	string _location;
	FILE* _file;

	this(IVFSPackage container, string location, FILE* file)
	{
		_container = container;
		_location = location;
		_file = file;
	}
}


class VFSQPKFile : IVFSFile
{
public:
	long read(void* ptr, size_t size, size_t n)
	{
		fseek(_archiveFile, _offset + _filePointer, SEEK_SET);

		if (_filePointer + n * size > _size)
			n = (_size - _filePointer) / size;

		immutable long bRead = fread(ptr, size, n, _archiveFile);
		_filePointer += bRead * size;
		return bRead;
	}

	long read(void[] buffer)
	{
		return read(buffer.ptr, void.sizeof, buffer.length);
	}

	long write(const void* ptr, size_t size, size_t n) // @suppress(dscanner.suspicious.unused_parameter)
	{
		assert(false, "Cannot write to QPK files!");
	}

	long write(const void[] buffer) // @suppress(dscanner.suspicious.unused_parameter)
	{
		assert(false, "Cannot write to QPK files!");
	}

	long seek(long offset, IVFSFile.Seek whence)
	{
		final switch (whence) with (IVFSFile.Seek)
		{
			case set:
				_filePointer = offset;
				break;

			case current:
				_filePointer += offset;
				break;

			case end:
				_filePointer = _size - offset;
				break;
		}

		enforce!VFSException(_filePointer >= 0 && _filePointer < _size, "File pointer outside of file!".tr);
		return _filePointer;
	}

	long tell() nothrow { return _filePointer; }

	@property long size() nothrow { return cast(long) _size; }

	@property IVFSPackage container() nothrow { return _container; }

	@property string location() nothrow { return _location; }

package:
	IVFSPackage _container;
	string _location;
	FILE* _archiveFile;
	uint _offset;
	uint _size;
	long _filePointer;

	this(IVFSPackage container, string location, FILE* archiveFile, uint offset, uint size)
	{
		_container = container;
		_location = location;
		_archiveFile = archiveFile;
		_offset = offset;
		_size = size;
	}
}