module qrescent.core.engine;

import core.memory : GC;
import core.thread;
import std.typecons : Tuple;
import std.stdio : stdout;
import std.exception : collectException, enforce;
import std.string : format;

import derelict.util.exception;
import derelict.opengl;
import derelict.openal;
import derelict.sndfile.sndfile;
import derelict.glfw3;
import sdlang;
import gl3n.linalg;

import qrescent.core.servers.graphics;
import qrescent.core.servers.input;
import qrescent.core.servers.audio;
import qrescent.core.servers.physics3d;
import qrescent.core.servers.language;
import qrescent.core.servers.language : tr;
import qrescent.core.qomproc;
import qrescent.core.qomprocgui;
import qrescent.core.vfs;
import qrescent.core.exceptions;
import qrescent.core.error;
import qrescent.resources.loader;
import qrescent.resources.scene;
import qrescent.resources.sprite : Sprite;
import qrescent.resources.shader : ShaderProgram;

/**
This struct provides interaction with the engine core, and contains
various information about the engine, how it was booted up,
the current scene and much more.
*/
struct EngineCore
{
    @disable this();
    @disable this(this);

public static:
    enum vMajor = 0; /// Major version of the engine.
    enum vModerate = 2; /// Moderate version of the engine.
    enum vMinor = 0; /// Minor version of the engine.
    enum vGitHash = "c50cefa"; /// Abbreviated git hash of the current engine's build.

    bool developer; /// If developer messages should be printed.

    /// Info about command line arguments.
    struct CmdArgs
    {
        string[] files; /// A list of packages to include.
        string[] commands; /// Commands later forwarded to Qomproc.
        bool showHelp; /// If help should be displayed.
        bool noStdOut; /// If output on stdout should be disabled.
    }

    /// Struct holding project settings.
    struct ProjectSettings
    {
        private alias vec2i = Tuple!(int, "x", int, "y");

        vec2i viewportSize; /// The size of the viewport in pixels.
        vec2i windowSize; /// The size of the window in pixels.
        string startScene; /// The path to the scene to start the game on.
        string qomprocAutoexec; /// The path to the file immediately executed by Qomproc.
        int targetFrameRate; /// The frame rate the engine should target to keep.
        string windowTitle; /// The title of the window.
        int audioChannels; /// How many audio channels should be allocated.
        string translation; /// Path to the translation to load, if given.
        string gameName; /// The internal name of the game.

        string fallbackShader; /// Shader to fall back to on error.
        string fallbackTexture; /// Texture to fall back to on error.
        string fallbackMaterial; /// Material to fall back to on error.
        string fallbackFont; /// Font to fall back to on error.
        string fallbackMesh; /// Mesh to fall back to on error.
        string fallbackSprite; /// Sprite to fall back to on error.

        vec3 physicsGravity = vec3(0, -9.81, 0); /// Constant gravity factor that is applied to physics objects.
        float physicsIgnoreInterpenetrationThreshold = 0.01; /// Threshold up to which to ignore interepenetration to avoid jittering.
        float physicsInterpenetrationResolutionFactor = 0.9; /// Fraction to which to resolve interpenetration to avoid jittering.
    }

    bool showPaused = true; /// If the "paused" text should be displayed when the game is paused.
    bool showLoading = true; /// If the "loading" text should be displayed when loading a scene.

    /**
    Starts the game loop.

    Params:
        mainPackage = If not `null`, the package that gets loaded after `qrescent.qpk`.
        cmdArgs = The parsed command line arguments.
    */
    void run(string mainPackage, CmdArgs cmdArgs)
    {
        if (Exception ex = collectException(_initialize(mainPackage, cmdArgs)))
        {
            showFatalError("Qrescent failed to start up due to an error. I'm sorry for the inconvenience.\nThe error message was: ".tr ~ ex.msg, ex.toString(), "Failed to start up :(".tr);
            return;
        }

        _running = true;
        Duration difference = dur!"msecs"(1);

    tryLabel:
        try
        {
            while (_running)
            {
                AudioServer._updateStreams();

                GraphicsServer._prepareRender();
                glfwPollEvents();

                if (GraphicsServer.window.shouldClose)
                    Qomproc.append("quit");

                immutable MonoTime old = MonoTime.currTime;
                Duration frameTime = _fpsWaitTime + difference;
                if (frameTime.isNegative)
                    frameTime = Duration.zero;

                if (_scene)
                {
                    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
                    _scene.systems.run(frameTime);
                }

                difference = MonoTime.currTime - old;

                Qomproc.cycle();
                QomprocGUI._update();

                if (_sceneLoadPath)
                    _performSceneChange();
                else
                {
                    if (_paused && showPaused)
                    {
                        _textShader.bind();
                        _textShader.setUniform("projection", _textProjectionMatrix);
                        _textShader.setUniform("transform", _textTransformMatrix);
                        _textPausedSprite.texture.bind();
                        _textPausedSprite.mesh.bind();
                        _textPausedSprite.mesh.draw();
                    }

                    QomprocGUI._render();
                    GraphicsServer._finishRender();
                }

                Thread.sleep(frameTime);
                _upTime += frameTime;
            }

            _shutdown();
        }
        catch (Exception ex)
        {
            if (_scene)
            {
                _scene = null;
                _scene.destroy();
            }

            QomprocGUI.fullscreen = true;

            Qomproc.println("===== INTERNAL EXCEPTION OCCURRED :( =======================".tr
            ~ "\nQrescent has encountered an unhandled exception, and has therefore terminated the\ncurrent scene. Unsaved changes may have been lost. I'm sorry for the inconvenience.".tr
            ~ "\n------------------------------------------------------------\n"
            ~ ex.toString
            ~ "\n============================================================");

            goto tryLabel;
        }
        catch (Throwable ex) // @suppress(dscanner.suspicious.catch_em_all) I know what I'm doing
        {
            import core.stdc.stdlib : exit, EXIT_FAILURE;

            showFatalError("Qrescent encountered a fatal error and has to shut down.\nI'm sorry for the inconvenience. The error message was: ".tr ~ ex.msg,
                ex.toString(),
                "Fatal error :(".tr);
            
            exit(EXIT_FAILURE);
        }
    }

    /**
    Parses command line arguments into a struct that contains engine options,
    packages to load and commands to execute.

    Params:
        args = The command line arguments as retrieved by the `main` function.
    
    Returns: The parsed command line arguments.
    Throws: `CoreException` if an invalid command line argument is given.
    */
    CmdArgs parseCmdArgs(string[] args)
    {
        CmdArgs result;
        bool parsingFiles;

        for (size_t argPos = 1; argPos < args.length; ++argPos)
        {
            switch (args[argPos])
            {
                case "-file":
                    parsingFiles = true;
                    continue;

                case "-nostdout":
                    result.noStdOut = true;
                    continue;

                case "--help":
                case "-h":
                    parsingFiles = false;
                    result.showHelp = true;
                    continue;

                default:
                    if (args[argPos][0] == '+' && args[argPos].length > 1)
                    {
                        parsingFiles = false;
                        result.commands ~= args[argPos][1..$];
                        continue;
                    }

                    if (parsingFiles)
                    {
                        result.files ~= args[argPos];
                        continue;
                    }

                    throw new CoreException("Unknown command line argument " ~ args[argPos]);
            }
        }

        return result;
    }

    /**
    Changes the scene to the given path at the beginning of the next frame.
    If path is "<none>", it will just unload the current scene.
    It path is `null`, it cancels a pending scene change.

    Params:
        path = The path of the scene to change to.
    */
    void changeSceneTo(string path) @safe nothrow
    {
        _sceneLoadPath = path;
    }

    /// The current target framerate.
    /// Throws: `CoreException` if an invalid framerate is given.
    @property void targetFrameRate(int frameRate) @safe // @suppress(dscanner.style.doc_missing_params)
    {
        enforce!CoreException(frameRate >= 1, "Invalid framerate given.".tr);

        _fpsWaitTime = dur!"msecs"(1000 / frameRate);
    }

    /// The project settings of the currently loaded game.
    @property ProjectSettings projectSettings() nothrow @nogc @safe { return _settings; } // @suppress(dscanner.style.doc_missing_returns)

    /// If the game is currently paused.
    @property void paused(bool value) nothrow @nogc @safe { _paused = value; } // @suppress(dscanner.style.doc_missing_params)

    /// ditto
    @property bool paused() nothrow @nogc @safe { return _paused || QomprocGUI.visible; }

private static:
    bool _running;
    bool _paused;
    Duration _fpsWaitTime;
    Duration _upTime;
    ProjectSettings _settings;
    Scene _scene;
    string _sceneLoadPath;

    mat4 _textProjectionMatrix = mat4.orthographic(0, 800, 600, 0, -1, 1);
    mat4 _textTransformMatrix = mat4.translation(400, 300, 0);
    Sprite _textLoadingSprite, _textPausedSprite;
    ShaderProgram _textShader;

    void _performSceneChange()
    {
        try
        {
            if (_scene)
            {
                _scene = null;
                _scene.destroy();
            }

            if (_sceneLoadPath != "<none>")
            {
                Qomproc.dprintfln("Changing scene to '%s'...".tr, _sceneLoadPath);

                QomprocGUI._render();

                if (showLoading)
                {
                    _textShader.bind();
                    _textShader.setUniform("projection", _textProjectionMatrix);
                    _textShader.setUniform("transform", _textTransformMatrix);
                    _textLoadingSprite.texture.bind();
                    _textLoadingSprite.mesh.bind();
                    _textLoadingSprite.mesh.draw();
                }

                GraphicsServer._finishRender();

                Scene scene = cast(Scene) ResourceLoader.load(_sceneLoadPath);
                enforce!SceneException(scene, "File '%s' is not a scene.".tr.format(_sceneLoadPath));

                _scene = scene;
            }
        }
        catch (Exception ex)
        {
            Qomproc.println("Failed to change scene: ".tr ~ ex.msg);
        }
        finally
        {
            QomprocGUI.fullscreen = _scene is null;
            QomprocGUI.visible = _scene is null;
            _sceneLoadPath = null;
            _paused = false;
        }
    }

    void _loadProjectSettings(string path)
    {
        Tag root;
        {
            IVFSFile file = VFS.getFile(path);
            char[] source = new char[file.size];
            file.read(source);
            file.destroy();

            root = parseSource(source.idup, path);
        }

        {
            Tag windowSize = root.expectTag("window-size");

            _settings.windowSize = ProjectSettings.vec2i(
                windowSize.values[0].get!int,
                windowSize.values[1].get!int
            );
        }

        {
            Tag viewportSize = root.expectTag("viewport-size");

            _settings.viewportSize = ProjectSettings.vec2i(
                viewportSize.values[0].get!int,
                viewportSize.values[1].get!int
            );
        }

        _settings.startScene = root.expectTagValue!string("start-scene");
        _settings.gameName = root.expectTagValue!string("game-name");

        {
            Tag fallbacks = root.expectTag("fallbacks");

            _settings.fallbackShader = fallbacks.expectTagValue!string("shader");
            _settings.fallbackTexture = fallbacks.expectTagValue!string("texture");
            _settings.fallbackMaterial = fallbacks.expectTagValue!string("material");
            _settings.fallbackFont = fallbacks.expectTagValue!string("font");
            _settings.fallbackMesh = fallbacks.expectTagValue!string("mesh");
            _settings.fallbackSprite = fallbacks.expectTagValue!string("sprite");
        }

        _settings.translation = root.getTagValue!string("load-translation", null);
        _settings.qomprocAutoexec = root.getTagValue!string("qomproc-autoexec", null);
        _settings.targetFrameRate = root.getTagValue!int("target-framerate", 60);
        _settings.windowTitle = root.getTagValue!string("window-title", "Qrescent Engine");
        _settings.audioChannels = root.getTagValue!int("audio-channels", 8);

        if (Tag physics = root.getTag("physics"))
        {
            if (Tag gravity = physics.getTag("gravity"))
                _settings.physicsGravity = vec3(gravity.values[0].get!float, gravity.values[1].get!float,
                    gravity.values[2].get!float);
            
            _settings.physicsIgnoreInterpenetrationThreshold = physics.getTagValue!float(
                "ignore-interpenetration-threshold", _settings.physicsIgnoreInterpenetrationThreshold);
            _settings.physicsInterpenetrationResolutionFactor = physics.getTagValue!float(
                "interpenetration-resolution-factor", _settings.physicsInterpenetrationResolutionFactor);
        }
    }

    void _initialize(string mainPackage, CmdArgs cmdArgs)
    {
        if (SharedLibLoadException ex = cast(SharedLibLoadException) collectException(_initLibraries()))
            throw new CoreException("Could not load necessary shared library: " ~ ex.msg, __FILE__, __LINE__, ex);

        if (!cmdArgs.noStdOut)
            Qomproc.addOutput(new QomprocOutputFile(stdout));
        Qomproc.addOutput(new QomprocOutputGUI());
        Qomproc.printfln("Qrescent %d.%d.%d.%s", vMajor, vModerate, vMinor, vGitHash);

        _initVFS(mainPackage, cmdArgs);
        
        if (Exception ex = collectException(_loadProjectSettings("res://project.cfg")))
            throw new CoreException("Failed to load project settings: " ~ ex.msg);

        VFS.initialize(_settings.gameName);
        ResourceLoader.registerDefaultLoaders();
        LanguageServer._initialize(_settings.translation);

        _initQomproc(cmdArgs);

        if (missingSymbols.length > 0)
        {
            Qomproc.println("The following symbols could not be found while loading dynlibs:".tr);
            foreach (string symbol; missingSymbols)
                Qomproc.println("    " ~ symbol);
        }

        Qomproc.println("GLFW initializing...".tr);
        if (!glfwInit())
            throw new CoreException("Failed to initialize GLFW.".tr);

        if (Exception ex = collectException(_initServers()))
            throw new CoreException("Failed to initialize servers: ".tr ~ ex.msg, __FILE__, __LINE__, ex);

        _initInternalECS();

        _textLoadingSprite = cast(Sprite) ResourceLoader.load("res://sprites/loading.spr");
        _textPausedSprite = cast(Sprite) ResourceLoader.load("res://sprites/paused.spr");
        _textShader = cast(ShaderProgram) ResourceLoader.load("res://shaders/unshaded.shd");

        // Execute Qomproc autoexec
        if (_settings.qomprocAutoexec)
        {
            Qomproc.execute(`exec "` ~ _settings.qomprocAutoexec ~ `"`);
            Qomproc.flush();
        }

        Qomproc.unregisterQCMD("stuffcmds");

        targetFrameRate = _settings.targetFrameRate;

        Qomproc.println("Loading start scene...".tr);
        changeSceneTo(_settings.startScene);
    }

    void _shutdown()
    {
        Qomproc.saveArchiveToFile("user://config.cfg");

        GraphicsServer._shutdown();
        InputServer._shutdown();
        AudioServer._shutdown();
        QomprocGUI._shutdown();

        ResourceLoader.freeAll();
        GC.collect();
        ResourceLoader.cleanCache();

        VFS.freeAll();

        Qomproc.println("Bye.");
    }

    void _initLibraries()
    {
        DerelictGLFW3.missingSymbolCallback = &missingSymbolCallback;
        DerelictGL3.missingSymbolCallback = &missingSymbolCallback;
        DerelictAL.missingSymbolCallback = &missingSymbolCallback;
        DerelictSndFile.missingSymbolCallback = &missingSymbolCallback;

        import std.file : getcwd;
        string libGlfwPath, libSndFilePath;

        version (Posix)
        {
            libGlfwPath = "/libglfw.so.3.2";
            libSndFilePath = "/libsndfile.so.1.0.28";
        }

        if (collectException(DerelictGLFW3.load()))
            DerelictGLFW3.load(getcwd ~ libGlfwPath);
        
        DerelictGL3.load();
        DerelictAL.load();

        if (collectException(DerelictSndFile.load()))
            DerelictSndFile.load(getcwd ~ libSndFilePath);
    }

    void _initQomproc(CmdArgs cmdArgs)
    {
        Qomproc.initSystemQCMDs();

        // Register internal QCMDs
        Qomproc.registerQCMD("stuffcmds", QCMD(delegate void(string[] args, Qomproc.CommandSource cmdsrc) // @suppress(dscanner.suspicious.unused_parameter)
        {
            import std.array : join;

            Qomproc.append(cmdArgs.commands.join("\0"));
            cmdArgs.commands.length = 0;
        },
        "Add command line statements to Qomproc buffer."));

        Qomproc.registerQCMD("loadscene", QCMD(delegate void(string[] args, Qomproc.CommandSource cmdsrc)
        {
            enforce!QomprocException(args.length >= 2, "Expected scene to load.".tr);

            changeSceneTo(args[1]);
        },
        "Load the given scene. If argument is '<none>', unload current scene.".tr));

        Qomproc.registerQCMD("quit", QCMD(delegate void(string[] args, Qomproc.CommandSource cmdsrc) // @suppress(dscanner.suspicious.unused_parameter)
        {
            _running = false;
        },
        "Stops the game immediately.".tr));

        Qomproc.registerQCMD("collectgarbage", QCMD(delegate void(string[] args, Qomproc.CommandSource cmdsrc)
        {
            import core.memory : GC;

            GC.collect();
            GC.minimize();
        },
        "Initiate a GC cycle, and free memory if possible.".tr));

        Qomproc.registerQCMD("stats", QCMD(delegate void(string[] args, Qomproc.CommandSource cmdsrc)
        {
            import core.memory : GC;

            auto stats = GC.stats();
            auto profileStats = GC.profileStats();

            immutable long upSeconds = _upTime.total!"seconds";

            Qomproc.printfln("Engine uptime: %02d:%02d:%02d".tr, upSeconds / 3600, upSeconds / 60 % 60, upSeconds % 60);

            Qomproc.printfln("Used memory: %d bytes (%.2f KiB)".tr, stats.usedSize, stats.usedSize / 1024f);
            Qomproc.printfln("Free memory for allocation: %d bytes (%.2f KiB)".tr, stats.freeSize, stats.freeSize / 1024f);
            
            Qomproc.printfln("\nGC largest collection time: %d ns".tr, profileStats.maxCollectionTime.total!"nsecs");
            Qomproc.printfln("GC total collection time: %d ns".tr, profileStats.totalCollectionTime.total!"nsecs");
            Qomproc.printfln("GC largest thread pause: %d ns".tr, profileStats.maxPauseTime.total!"nsecs");
            Qomproc.printfln("GC total thread pause: %d ns".tr, profileStats.totalPauseTime.total!"nsecs");
            Qomproc.printfln("GC collections since startup: %d".tr, profileStats.numCollections);

            if (!_scene)
                Qomproc.println("\nCurrently not in a scene.".tr);
            else
                Qomproc.printfln("\nCurrent scene: %s".tr, _scene.path);
        },
        "Prints internal information about the engine.".tr));

        Qomproc.registerQCMD("version", QCMD(delegate void(string[] args, Qomproc.CommandSource cmdsrc)
        {
            import std.conv : to;

            version (linux)
                enum platform = "Linux";
            else version (Win32)
                enum platform = "Windows 32-bit";
            else version (Win64)
                enum platform = "Windows 64-bit";
            else
                enum platform = "Unknown";

            enum versionStr = "Qrescent Version " ~ vMajor.to!string ~ "." ~ vModerate.to!string
                ~ "." ~ vMinor.to!string ~ "." ~ vGitHash ~ " " ~ platform;

            Qomproc.println(versionStr);
            Qomproc.println("Built: " ~ __TIME__ ~ " " ~ __DATE__);
        },
        "Prints the version of the engine.".tr));

        Qomproc.registerQVAR("paused", QVAR(&_paused, "If the game is currently paused.".tr));
        Qomproc.registerQVAR("developer", QVAR(&developer, "If development messages should be printed.".tr));

        Qomproc.registerQVAR("con_showpaused",
            QVAR(&showPaused, "If the 'paused' text should be displayed when paused.".tr, QVAR.Flags.archive));
        Qomproc.registerQVAR("con_showloading",
            QVAR(&showLoading, "If the 'loading' text should be displayed when loading scenes.".tr, QVAR.Flags.archive));

        Qomproc.println("Qomproc initialized.".tr);
    }

    void _initVFS(string mainPackage, CmdArgs cmdArgs)
    {
        VFS.addPackage("qrescent.qpk");
        if (mainPackage)
            VFS.addPackage(mainPackage);
        
        foreach (string file; cmdArgs.files)
            if (Exception ex = collectException(VFS.addPackage(file)))
                Qomproc.printfln("Failed to load package '%s': %s".tr, file, ex.msg);
    }

    void _initServers()
    {
        ResourceLoader.initialize();

        GraphicsServer._initialize();
        GraphicsServer.setViewportSize(_settings.viewportSize.x, _settings.viewportSize.y);

        AudioServer._initialize(_settings.audioChannels);
        InputServer._initialize();

        QomprocGUI._initialize();

        Physics3DServer.gravity = _settings.physicsGravity;
        Physics3DServer.ignoreInterpenetrationThreshold = _settings.physicsIgnoreInterpenetrationThreshold;
        Physics3DServer.interpenetrationResolutionFactor = _settings.physicsInterpenetrationResolutionFactor;
    }

    void _initInternalECS()
    {
        import qrescent.resources.scene : SceneLoader;
        import qrescent.components.transform : Transform2DComponent, Transform3DComponent;
        import qrescent.components.camera : CameraComponent;
        import qrescent.components.mesh : MeshComponent;
        import qrescent.components.sprite : SpriteComponent;
        import qrescent.components.text : TextComponent;
        import qrescent.components.light : LightComponent;
        import qrescent.components.physics : Physics3DComponent;

        import qrescent.systems.render2d : Render2DSystem;
        import qrescent.systems.render3d : Render3DSystem;
        import qrescent.systems.physics3d : Physics3DSystem;

        SceneLoader.registerComponentLoader("transform2D", &Transform2DComponent.loadFromTag);
        SceneLoader.registerComponentLoader("transform3D", &Transform3DComponent.loadFromTag);
        SceneLoader.registerComponentLoader("camera", &CameraComponent.loadFromTag);
        SceneLoader.registerComponentLoader("mesh", &MeshComponent.loadFromTag);
        SceneLoader.registerComponentLoader("sprite", &SpriteComponent.loadFromTag);
        SceneLoader.registerComponentLoader("text", &TextComponent.loadFromTag);
        SceneLoader.registerComponentLoader("light", &LightComponent.loadFromTag);
        SceneLoader.registerComponentLoader("physics3D", &Physics3DComponent.loadFromTag);

        SceneLoader.registerSystemLoader("render2D", &Render2DSystem.loadFromTag);
        SceneLoader.registerSystemLoader("render3D", &Render3DSystem.loadFromTag);
        SceneLoader.registerSystemLoader("physics3D", &Physics3DSystem.loadFromTag);
    }
}

private:

string[] missingSymbols;

ShouldThrow missingSymbolCallback(string symbolName)
{
    missingSymbols ~= symbolName;
    return ShouldThrow.No;
}