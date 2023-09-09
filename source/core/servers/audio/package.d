module qrescent.core.servers.audio;

public
{
    import qrescent.core.servers.audio.bus;
    import qrescent.core.servers.audio.sample;
    import qrescent.core.servers.audio.stream;
}

import std.exception : enforce;
import std.algorithm : clamp;

import derelict.openal;
import derelict.sndfile.sndfile;
import gl3n.linalg;

import qrescent.core.servers.language : tr;
import qrescent.core.qomproc;
import qrescent.core.exceptions;
import qrescent.resources.sound;

/**
The AudioServer provides low-level functions for playing samples and
streams, setting listener properties and managing busses.
*/
struct AudioServer
{
    @disable this();
    @disable this(this);

public static:
    /// Meta data given for playing samples or streams.
    struct PlayInfo
    {
        string audioBus = "master"; /// Name of the audio bus to use.
        vec3 position = vec3(0); /// Position to play the sound at.
        float gain = 1f; /// The gain of the sound, relative to the used bus.
        bool looping; /// If the sound should be looped.
        ulong loopPoint; /// Streams only! The sample to jump to on loop.
    }

    /**
    Sets a new location for the listener.

    Params:
        location = The location of the listener.
    */
    void setListenerLocation(vec3 location) nothrow
    {
        alListener3f(AL_POSITION, location.x, location.y, location.z);
    }

    /**
    Sets a new gain for the listener.

    Params:
        gain = The gain of the listener, between 0 and 1.
    */
    void setListenerGain(float gain) nothrow
    {
        alListenerf(AL_GAIN, clamp(gain, 0, 1));
    }

    /**
    Gets the audio bus with the given name.

    Params:
        name = The name of the audio bus.

    Returns: The requested audio bus.
    Throws: `AudioException` if the given bus does not exist.
    */
    AudioBus getBus(string name) @safe
    {
        AudioBus* bus = name in _busses;
        enforce!AudioException(bus, "No AudioBus named '%s' exists.".tr.format(name));

        return *bus;
    }

    /**
    Adds a new bus with the given name.
    Also registeres a "snd_<bus name>" QCMD which is used for changing the
    gain of the associated bus.

    Params:
        name = The name of the new audio bus.

    Returns: The newly created audio bus.
    Throws: `AudioException` if the bus already exists.
    */
    AudioBus addBus(string name)
    {
        enforce!AudioException(!(name in _busses), "AudioBus named '%s' already exists.".tr.format(name));

        AudioBus newBus = new AudioBus();
        
        Qomproc.registerQCMD("snd_" ~ name, QCMD(delegate void(string[] args, Qomproc.CommandSource cmdsrc) // @suppress(dscanner.suspicious.unused_parameter)
        {
            import std.conv : to;

            if (args.length == 1)
            {
                Qomproc.printfln("Volume for audio bus '%s' is %.2f.".tr, name, newBus.gain);
                return;
            }

            newBus.gain = args[1].to!float;
        },
        "Set the volume for the '%s' bus.".tr.format(name)));

        _busses[name] = newBus;
        return newBus;
    }

    /**
    Removes the bus with the given name, and also unregisteres the associated volume QCMD.

    Params:
        name = The name of the audio bus.
    */
    void removeBus(string name)
    {
        if (name in _busses)
        {
            _busses[name].destroy();
            _busses.remove(name);

            Qomproc.unregisterQCMD("snd_" ~ name);
        }
    }

    /**
    Stops all currently playing sounds, including streams.
    */
    void stopAll()
    {
        foreach (AudioSampleChannel channel; _sampleChannels)
            channel.stop();

        _streamChannel.stop();
    }

    /**
    Plays an audio sample. If no channels are available, this will be logged to
    the Qomproc.

    Params:
        channel = The channel to play the sound at. If -1, picks the first free one.
        buffer = The SoundSample instance to use.
        info = Meta data used for playing the sample.

    Returns: Handle to the playing sound.
    Throws: `AudioException` if an invalid channel is given.
    */
    AudioSampleChannel playSample(int channel, SoundSample buffer, PlayInfo info = PlayInfo.init)
    {
        enforce!AudioException(channel < cast(int) _sampleChannels.length, "Invalid sound channel!".tr);
        
        AudioSampleChannel activeChannel;

        if (channel < 0)
        {
            foreach (AudioSampleChannel sampleChannel; _sampleChannels)
            {
                immutable AudioChannel.State state = sampleChannel.state;
                if (state == AudioChannel.State.initial || state == AudioChannel.State.stopped)
                {
                    activeChannel = sampleChannel;
                    goto channelFound;
                }
            }

            Qomproc.println("No free audio channels left!".tr);
            return null;
        }
    channelFound:

        activeChannel._audioBus = _busses[info.audioBus];
        activeChannel.gain = info.gain;
        activeChannel.position = info.position;
        activeChannel.looping = info.looping;
        activeChannel._setBuffer(buffer);

        activeChannel.play();
        return activeChannel;
    }

    /**
    Plays an audio stream.

    Params:
        buffer = The SoundStream instance to use.
        info = Meta data used for playing the stream.

    Returns: Handle to the playing stream.
    */
    AudioStreamChannel playStream(SoundStream buffer, PlayInfo info = PlayInfo.init)
    {
        _streamChannel._audioBus = _busses[info.audioBus];
        _streamChannel.gain = info.gain;
        _streamChannel.position = info.position;
        _streamChannel.looping = info.looping;
        _streamChannel.loopPoint = info.loopPoint;
        _streamChannel._setBuffer(buffer);

        _streamChannel.play();
        return _streamChannel;
    }

package(qrescent.core) static:
    void _initialize(size_t channels = 8) // @suppress(dscanner.style.doc_missing_throw)
    {
        Qomproc.println("AudioServer initializing...".tr);

        // Open default device
        _device = alcOpenDevice(null);
        _context = alcCreateContext(_device, null);

        alcMakeContextCurrent(_context);

        _sampleChannels.length = channels;
        for (size_t i; i < channels; ++i)
            _sampleChannels[i] = new AudioSampleChannel();
        
        _streamChannel = new AudioStreamChannel();

        // Create master AudioBus
        addBus("master");

        import qrescent.resources.loader : ResourceLoader;

        Qomproc.registerQCMD("playsound", QCMD(delegate void(string[] args, Qomproc.CommandSource cmdsrc) // @suppress(dscanner.suspicious.unused_parameter)
        {
            enforce!QomprocException(args.length >= 2, "Expected file to play.".tr);

            SoundSample buffer = cast(SoundSample) ResourceLoader.load(args[1]);
            enforce!QomprocException(buffer, "Given file is not a SoundSample.".tr);

            playSample(-1, buffer);
        },
        "Plays the specified sound at the first free channel.".tr));

        Qomproc.registerQCMD("changemus", QCMD(delegate void(string[] args, Qomproc.CommandSource cmdsrc)
        {
            import std.conv : to;

            enforce!QomprocException(args.length >= 2, "Expected file to play.".tr);

            SoundStream buffer = cast(SoundStream) ResourceLoader.load(args[1]);
            enforce!QomprocException(buffer, "Given file is not a SoundStream.".tr);

            PlayInfo info;

            if (args.length >= 3 && args[2] == "looped")
                info.looping = true;

            if (args.length >= 4)
                info.loopPoint = args[3].to!ulong;

            playStream(buffer, info);
        },
        "Changes the background music to the specified file.".tr));

        Qomproc.registerQCMD("stopmus", QCMD(delegate void(string[] args, Qomproc.CommandSource cmdsrc) // @suppress(dscanner.suspicious.unused_parameter)
        {
            _streamChannel.stop();
        },
        "Stops the current background music.".tr));
    }

    void _shutdown()
    {
        Qomproc.println("AudioServer shutting down...".tr);

        foreach (AudioSampleChannel channel; _sampleChannels)
            channel.destroy();

        alcCloseDevice(_device);
    }

    void _updateStreams()
    {
        _streamChannel._update();
    }

    package void _recalculateChannelGains(AudioBus bus) nothrow @trusted
    {
        try
        {
            foreach (AudioSampleChannel channel; _sampleChannels)
                if (channel._audioBus == bus)
                    alSourcef(channel._source, AL_GAIN, channel._gain * bus._gain);

            if (_streamChannel._audioBus == bus)
                alSourcef(_streamChannel._source, AL_GAIN, _streamChannel._gain * bus._gain);
        }
        catch (Exception ex) {}
    }

package static:
    ALCdevice* _device;
    ALCcontext* _context;

    AudioSampleChannel[] _sampleChannels;
    AudioStreamChannel _streamChannel;

    AudioBus[string] _busses;
}

/**
Represents an audio channel of any kind. An instance of this class
also gets returned as a handle by the AudioServer, if requested
to play a sample or stream.
*/
abstract class AudioChannel
{
public:
    ~this()
    {
        alDeleteSources(1, &_source);
    }

    /// The state of a channel.
    enum State
    {
        initial = AL_INITIAL, /// Channel has never played a sound before.
        playing = AL_PLAYING, /// Channel is currently playing.
        paused = AL_PAUSED, /// Channel has a sound that is currently paused.
        stopped = AL_STOPPED /// Channel playback has ended or been stopped.
    }

    /// The position from where this sound is playing.
    @property vec3 position() nothrow @trusted // @suppress(dscanner.style.doc_missing_returns)
    {
        float x, y, z;
        alGetSource3f(_source, AL_POSITION, &x, &y, &z);
        return vec3(x, y, z);
    }

    /// ditto
    @property void position(vec3 value) const nothrow @trusted // @suppress(dscanner.style.doc_missing_params)
    {
        alSource3f(_source, AL_POSITION, value.x, value.y, value.z);
    }
    
    /// The state of this channel.
    @property State state() const nothrow @trusted // @suppress(dscanner.style.doc_missing_returns)
    {
        int state;
        alGetSourcei(_source, AL_SOURCE_STATE, &state);
        return cast(State) state;
    }

    /// The gain of the channel.
    @property float gain() nothrow @safe // @suppress(dscanner.style.doc_missing_returns)
    {
        return _gain;
    }

    /// ditto
    @property void gain(float value) nothrow @safe // @suppress(dscanner.style.doc_missing_params)
    {
        _gain = clamp(value, 0.0f, 1.0f);
        AudioServer._recalculateChannelGains(_audioBus);
    }

    /**
    Plays or resumes playback on this channel.
    */
    abstract void play() @trusted;
    /**
    Pauses playback on this channel.
    */
    abstract void pause() @trusted;
    /**
    Stops playback on this channel and invalidates it.
    */
    abstract void stop() @trusted;

    /// If this channel is looping.
    @property abstract bool looping() nothrow @trusted;
    /// ditto
    @property abstract void looping(bool value) nothrow @trusted;

package:
    uint _source = void;
    float _gain = 1.0f;
    AudioBus _audioBus;

    this()
    {
        alGenSources(1, &_source);
    }
}