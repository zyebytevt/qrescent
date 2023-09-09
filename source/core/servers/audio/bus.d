module qrescent.core.servers.audio.bus;

import qrescent.core.servers.audio;

import std.algorithm : clamp;

/**
An AudioBus is responsible for keeping a consistent volume factor
for all samples and streams that are played over this bus.
*/
class AudioBus
{
public:
    /// The gain of this audio bus, ranging from 0 to 1.
    @property float gain() nothrow @safe // @suppress(dscanner.style.doc_missing_returns)
    {
        return _gain;
    }

    /// ditto
    @property void gain(float value) nothrow @safe // @suppress(dscanner.style.doc_missing_params)
    {
        _gain = clamp(value, 0.0f, 1.0f);
        AudioServer._recalculateChannelGains(this);
    }

package:
    float _gain = 1;
}