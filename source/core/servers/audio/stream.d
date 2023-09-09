module qrescent.core.servers.audio.stream;

import core.thread : Thread;
import std.datetime;

import derelict.openal;
import derelict.sndfile.sndfile;

import qrescent.core.servers.audio;
import qrescent.core.exceptions;
import qrescent.resources.sound;

/**
This class represents an audio channel that is responsible
for playing streams. The stream can't be set directly;
use `AudioServer.playStream` for this purpose.
*/
class AudioStreamChannel : AudioChannel
{
public:
    ~this()
    {
        alDeleteSources(1, &_source);
        alDeleteBuffers(_bufferHandles.length, _bufferHandles.ptr);
    }

    override void play() @trusted
    {
        _isPlaying = true;
        alSourcePlay(_source);
    }

    override void pause() @trusted
    {
        _isPlaying = false;
        alSourcePause(_source);
    }

    override void stop() @trusted
    {
        alSourceStop(_source);
        _cleanBuffers();

        _isPlaying = false;
        _seek(0);
    }

    @property override bool looping() nothrow @safe
    {
        return _isLooping;
    }

    @property override void looping(bool value) nothrow @safe
    {
        _isLooping = value;
    }

    /// The sample to jump to when looping.
    @property ulong loopPoint() nothrow @safe // @suppress(dscanner.style.doc_missing_returns)
    {
        return cast(ulong) _loopPoint;
    }

    /// ditto
    @property void loopPoint(ulong value) nothrow @safe // @suppress(dscanner.style.doc_missing_params)
    {
        _loopPoint = cast(size_t) value;
    }

package:
    void _setBuffer(SoundStream buffer)
    {
        stop();
        _buffer = buffer;
        _seek(0);

        size_t readBuffers;
        for (; readBuffers < _bufferHandles.length; ++readBuffers)
        {
            try
            {
                immutable uint bufferHandle = _getNextBuffer();
                _bufferHandles[readBuffers] = bufferHandle;
            }
            catch (EOFException) {}
        }

        alSourceQueueBuffers(_source, cast(int) readBuffers, _bufferHandles.ptr);
    }

    void _update() @trusted
    {
        if (!_isPlaying)
            return;

        int processed;
        alGetSourcei(_source, AL_BUFFERS_PROCESSED, &processed);

        if (processed > 0)
        {
            alSourceUnqueueBuffers(_source, processed, _bufferHandles.ptr);
            alDeleteBuffers(processed, _bufferHandles.ptr);

            size_t readBuffers;
            for (; readBuffers < processed; ++readBuffers)
            {
                try
                {
                    immutable uint bufferHandle = _getNextBuffer();
                    _bufferHandles[readBuffers] = bufferHandle;
                }
                catch (EOFException)
                {
                    if (_isLooping)
                    {
                        _seek(_loopPoint);

                        immutable uint bufferHandle = _getNextBuffer();
                        _bufferHandles[readBuffers] = bufferHandle;
                    }
                    else
                    {
                        _isPlaying = false;
                        break;
                    }
                }
            }

            alSourceQueueBuffers(_source, cast(int) readBuffers, _bufferHandles.ptr);
        }
    }

private:
    SoundStream _buffer;
    uint[4] _bufferHandles;
    size_t _loopPoint;
    size_t _currentPosition;
    
    bool _isLooping;
    bool _isPlaying;

    uint _getNextBuffer() @system
    {
        SF_INFO info = _buffer.info;

        AudioBuffer ab = sndfile_readFloats(_buffer.sndFile, info, 48_000);

        uint buffer;
        alGenBuffers(1, &buffer);

        alBufferData(buffer, info.channels == 1 ? AL_FORMAT_MONO_FLOAT32 : AL_FORMAT_STEREO_FLOAT32, ab.data.ptr,
            cast(int) (ab.remaining * float.sizeof), info.samplerate);

        return buffer;
    }

    void _seek(size_t point) @system
    {
        import core.stdc.stdio : SEEK_SET;
        
        if (_buffer)
        {
            sf_seek(_buffer.sndFile, point, SEEK_SET);
            _currentPosition = point;
        }
    }

    void _cleanBuffers()
    {
        int queued;
        alGetSourcei(_source, AL_BUFFERS_QUEUED, &queued);

        alSourceUnqueueBuffers(_source, queued, _bufferHandles.ptr);
        alDeleteBuffers(_bufferHandles.length, _bufferHandles.ptr);
    }
}

private:

struct AudioBuffer
{
    float[] data;
    sf_count_t remaining;
}

AudioBuffer sndfile_readFloats(SNDFILE* file, SF_INFO info, size_t frames)
{
    AudioBuffer ab;

    ab.data = new float[frames * info.channels];

    if ((ab.remaining = sf_read_float(file, ab.data.ptr, ab.data.length)) <= 0)
        throw new EOFException("");

    return ab;
}