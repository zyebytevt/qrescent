/**
System management module.

Copyright: © 2015-2016 Claude Merle
Authors: Claude Merle
License: This file is part of EntitySysD.

EntitySysD is free software: you can redistribute it and/or modify it
under the terms of the Lesser GNU General Public License as published
by the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

EntitySysD is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
Lesser GNU General Public License for more details.

You should have received a copy of the Lesser GNU General Public License
along with EntitySysD. If not, see $(LINK http://www.gnu.org/licenses/).
*/

module qrescent.ecs.stat;

public import core.time;


/**
 * Structure used in the system-manager to do some basic profiling.
 */
struct Stat
{
package:
    void start()
    {
        mLastTime = MonoTime.currTime;
        if (mFirstTime == MonoTime.zero)
        {
            mFirstTime = mLastTime;
            mMin = mMax = seconds(0);
            mRunCount = 0;
        }
    }

    void stop()
    {
        assert(mLastTime != MonoTime.zero);
        auto now = MonoTime.currTime;
        Duration dur = now - mLastTime;
        if (mMin == seconds(0) || dur < mMin)
            mMin = dur;
        if (mMax < dur)
            mMax = dur;

        mSum += dur;
        mRunCount++;
    }

    void update()
    {
        if (mRunCount != 0)
            mAvg = mSum / mRunCount;
        else
            mAvg = seconds(0);
        mSum = seconds(0);
        mFirstTime = MonoTime.zero;
    }

    void clear()
    {
        mMin = mMax = mSum = mAvg = seconds(0);
        mFirstTime = mLastTime = MonoTime.zero;
        mRunCount = 0;
    }

public:
    /**
     * Elapsed time since the last update (defined by rate parameter in the
     * statistic enabling function of the system-manager).
     */
    Duration elapsedTime() @property const
    {
        return mFirstTime == MonoTime.zero
             ? seconds(0)
             : MonoTime.currTime - mFirstTime;
    }

    deprecated("Please, use `average` instead.")
    alias averageDuration = average;
    deprecated("Please, use `min` instead.")
    alias minDuration = min;
    deprecated("Please, use `max` instead.")
    alias maxDuration = max;

    /**
     * Average duration of the profiled function (during the time defined by the
     * rate parameter in the statistic enabling function of the system-manager).
     */
    Duration average() @property const
    {
        return mAvg;
    }

    /**
     * Minimum measured duration of the profiled function (during the time
     * defined by the rate parameter in the statistic enabling function of
     * the system-manager).
     */
    Duration min() @property const
    {
        return mMin;
    }

    /**
     * Maximum measured duration of the profiled function (during the time
     * defined by the rate parameter in the statistic enabling function of
     * the system-manager).
     */
    Duration max() @property const
    {
        return mMax;
    }

    /**
     * Number of times the profiled function was called (during the time
     * defined by the rate parameter in the statistic enabling function of
     * the system-manager).
     */
    ulong runCount() @property const
    {
        return mRunCount;
    }

private:
    Duration        mMin;
    Duration        mMax;
    Duration        mSum;
    Duration        mAvg;
    ulong           mRunCount;
    MonoTime        mLastTime;
    MonoTime        mFirstTime;
}