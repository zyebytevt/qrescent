module qrescent.resources.sound;

import core.stdc.stdio : SEEK_CUR, SEEK_SET, SEEK_END;
import std.exception : enforce;

import derelict.openal.al;
import derelict.sndfile.sndfile;

import qrescent.core.servers.language : tr;
import qrescent.core.exceptions;
import qrescent.core.vfs;
import qrescent.resources.loader;

/**
Represents a chunk of audio that is loaded into memory
and can be played at any time almost instantly, and
a single sample can be played multiple times simultaneously.
*/
class SoundSample : Resource
{
public:
    /**
    Constructs a new sound sample.

    Params:
        channels = If the sample is mono (1) or stereo (2).
        sampleRate = The sample rate of the sample.
        data = The raw data to use.
    */
    this(int channels, int sampleRate, float[] data) nothrow @trusted
    {
        alGenBuffers(1, &_buffer);
        alBufferData(_buffer, channels == 1 ? AL_FORMAT_MONO_FLOAT32 : AL_FORMAT_STEREO_FLOAT32,
            data.ptr, cast(int) (data.length * float.sizeof), sampleRate);
    }

    ~this() nothrow @trusted
    {
        alDeleteBuffers(1, &_buffer);
    }

    /// The internal OpenAL id of this sample.
    @property uint buffer() const pure nothrow { return _buffer; } // @suppress(dscanner.style.doc_missing_returns)

private:
    uint _buffer;
}

/**
Represents a longer piece of audio that is loaded
into memory chunkwise, e.g. it is streamed from disk.
There could be possible latency when starting, and
no more than one instance of an individual SoundStream
can be played at any time.
*/
class SoundStream : Resource
{
public:
    /**
    Constructs a new sound stream.

    Params:
        vfsFile = The VFS file handle this stream will load chunks from.
        info = Information about the audio from SndFile.
        file = The internal SndFile file handle.
    */
    this(IVFSFile vfsFile, SF_INFO info, SNDFILE* file)
    {
        _info = info;
        _sndFile = file;
        _vfsFile = vfsFile;
    }

    ~this()
    {
        sf_close(_sndFile);
    }

    /// Information about the audio from SndFile.
    @property SF_INFO info() const pure nothrow { return _info; } // @suppress(dscanner.style.doc_missing_returns)
    /// The internal SndFile file handle.
    @property SNDFILE* sndFile() pure nothrow { return _sndFile; } // @suppress(dscanner.style.doc_missing_returns)

private:
    SF_INFO _info;
    SNDFILE* _sndFile;
    IVFSFile _vfsFile;
}

// ===== AUDIO LOADER FUNCTION =====

package:

Resource resLoadAudio(string path)
{
    static SF_VIRTUAL_IO vfsIO;

    if (!vfsIO.get_filelen)
    {
        vfsIO.get_filelen = &sfvioGetFilelen;
        vfsIO.seek = &sfvioSeek;
        vfsIO.read = &sfvioRead;
        vfsIO.write = &sfvioWrite;
        vfsIO.tell = &sfvioTell;
    }

    scope IVFSFile file = VFS.getFile(path);

    SF_INFO info;
    SNDFILE* sndFile = sf_open_virtual(&vfsIO, SFM_READ, &info, cast(void*) file);
    enforce!VFSException(sndFile, "Failed to open file '%s' for audio decoding.".tr.format(path));

    float[] data;
    float[] readBuf = new float[2048];

    long readSize;
    while ((readSize = sf_read_float(sndFile, readBuf.ptr, readBuf.length)) != 0)
        data ~= readBuf[0..cast(size_t) readSize];

    sf_close(sndFile);

    return new SoundSample(info.channels, info.samplerate, data);
}

Resource resLoadStreamingAudio(string path)
{
    static SF_VIRTUAL_IO vfsIO;

    if (!vfsIO.get_filelen)
    {
        vfsIO.get_filelen = &sfvioGetFilelen;
        vfsIO.seek = &sfvioSeek;
        vfsIO.read = &sfvioRead;
        vfsIO.write = &sfvioWrite;
        vfsIO.tell = &sfvioTell;
    }

    IVFSFile file = VFS.getFile(path);

    SF_INFO info;
    SNDFILE* sndFile = sf_open_virtual(&vfsIO, SFM_READ, &info, cast(void*) file);
    enforce!VFSException(sndFile, "Failed to open file '%s' for audio decoding.".tr.format(path));

    return new SoundStream(file, info, sndFile);
}

private:

extern(C) sf_count_t sfvioGetFilelen(void* userData) nothrow @trusted
{
    IVFSFile file = cast(IVFSFile) userData;

    return cast(sf_count_t) file.size;
}

extern(C) sf_count_t sfvioSeek(sf_count_t offset, int whence, void* userData) @trusted
{
    IVFSFile file = cast(IVFSFile) userData;

    IVFSFile.Seek vfsWhence;
    final switch (whence)
    {
        case SEEK_CUR: vfsWhence = IVFSFile.Seek.current; break;
        case SEEK_SET: vfsWhence = IVFSFile.Seek.set; break;
        case SEEK_END: vfsWhence = IVFSFile.Seek.end; break;
    }

    return cast(sf_count_t) file.seek(offset, vfsWhence);
}

extern(C) sf_count_t sfvioRead(void* ptr, sf_count_t count, void* userData) @trusted
{
    IVFSFile file = cast(IVFSFile) userData;

    return cast(sf_count_t) file.read(ptr, ubyte.sizeof, count);
}

extern(C) sf_count_t sfvioWrite(const void* ptr, sf_count_t count, void* userData) @trusted
{
    IVFSFile file = cast(IVFSFile) userData;

    return cast(sf_count_t) file.write(ptr, ubyte.sizeof, count);
}

extern(C) sf_count_t sfvioTell(void* userData) nothrow @trusted
{
    IVFSFile file = cast(IVFSFile) userData;

    return cast(sf_count_t) file.tell();
}