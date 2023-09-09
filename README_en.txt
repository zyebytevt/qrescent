This here is my submission for the physics engine. Since it is likely a bit bulkier compared to others,
I will only list the most important things here.

To run the program, simply execute "run.sh". However, since ZIP does not store ext4 permissions, it may
be necessary to make "run.sh" and "qphysics" executable. You can do this with "chmod +x <file>" or through
the GUI.

Files in the Archive
====================

Brief explanation of the files in the submission:

    libglfw.so.3.2 - Supplied GLFW Library
    libsndfile.so.1.0.28 - Supplied SNDFILE Library
    qphysics - The game itself
    qphysics.qpk - Qrescent Package for game content
    qrescent.qpk - Qrescent Package for engine content
    tools/fntcompile - Program for compiling Qrescent Fonts
    tools/qpklink - Program for compiling Qrescent Packages

A Qrescent Package is a self-created file format that became necessary because TAR and other uncompressed
archives did not easily allow streaming from them. In addition, with QPKs, I could remove unnecessary
stuff like permissions or file attributes, etc. qpklink does not currently offer the ability to unpack
QPKs, but if there is interest in the contents of these QPKs, I can gladly provide them.

Troubleshooting
===============

If for any reason the game does not start, it may be due to the libraries. I hope it doesn't happen,
but if it does, the following command on Debian-based systems may resolve the issue:

sudo apt install libglfw3 libsndfile1

The only dependencies that Qrescent has are GLFW, SNDFILE, OpenGL, and OpenAL. Up-to-date graphics
drivers, the aforementioned libraries, and a good audio driver should resolve any issues.

Source Code
===========

Only the source code of the engine has been provided because it contains relevant code for the
physics engine. If you are interested in other code, I can provide it upon request.

The structure of the code is as follows:
	qrescent - Root
	├─── components - Implements all components of the engine
	├─── core - Low-level code
	│ ├─── qomproc - Implementation of the Qrescent Command Processors
	│ ├─── servers - "Servers" are like interfaces between high and low-level
	│ │ ├─── audio
	│ │ ├─── graphics
	│ │ └─── physics3d
	│ └─── vfs - Implementation of the Virtual File System
	├─── ecs - Implementation of the Entity-Component-System system. Part of EntitySysD written by Claude Merle.
	├─── resources - Resources that can be loaded, cached, and freed during runtime.
	└─── systems - Implements all systems of the engine

The important files here are
- qrescent/core/servers/physics3d/package.d
- qrescent/core/servers/physics3d/shapes.d
- qrescent/components/physics.d
- qrescent/systems/physics3d.d
