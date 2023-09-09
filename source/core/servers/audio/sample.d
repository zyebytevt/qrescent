module qrescent.core.servers.audio.sample;

import derelict.openal;

import qrescent.core.servers.audio;
import qrescent.resources.sound;

/**
This class represents an audio channel that is responsible
for playing samples. The sample can't be set directly;
use `AudioServer.playSample` for this purpose.
*/
class AudioSampleChannel : AudioChannel
{
public:
    override void play() @trusted
    {
        alSourcePlay(_source);
    }

    override void pause() @trusted
    {
        alSourcePause(_source);
    }

    override void stop() @trusted
    {
        alSourceStop(_source);
    }

    @property override bool looping() nothrow @trusted
    {
        int loopValue;
        alGetSourcei(_source, AL_LOOPING, &loopValue);
        return loopValue == AL_TRUE;
    }

    @property override void looping(bool value) nothrow @trusted
    {
        alSourcei(_source, AL_LOOPING, value);
    }

package:
    this() {}

    void _setBuffer(SoundSample buffer)
    {
        if (_buffer == buffer)
            return;
        
        _buffer = buffer;

        if (_buffer)
            alSourcei(_source, AL_BUFFER, buffer.buffer);
        else
            alSourcei(_source, AL_BUFFER, 0);
    }

private:
    SoundSample _buffer;
}