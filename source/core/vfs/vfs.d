module qrescent.core.vfs.vfs;

import std.path;
import std.file : read, exists, isFile, mkdirRecurse;
import std.algorithm : canFind, findSplit;
import std.string : fromStringz, format, toLower, empty, capitalize;
import std.exception : enforce;
import std.typecons;
import core.stdc.stdlib : getenv;

import qrescent.core.servers.language : tr;
import qrescent.core.exceptions;
import qrescent.core.qomproc;
import qrescent.core.vfs;

/**
Represents the Qrescent VFS. It can load packages as either directories
or packed QPKs, and more recently loaded packages override older ones
(in memory!)
*/
struct VFS
{
    @disable this();
    @disable this(this);

public static:
    /**
    Initializes the VFS.
    */
    void initialize(string userDirName)
    {
        Qomproc.println("VFS initializing...".tr);
        
        version (Posix)
        {
            import core.sys.posix.unistd : getuid;
            import core.sys.posix.pwd : getpwuid;

            const(char)* homedir;

            synchronized
            {
                if ((homedir = getenv("HOME")) is null)
                    homedir = getpwuid(getuid()).pw_dir;
            }

            string configDir = homedir.fromStringz.idup ~ "/.config/" ~ userDirName;
            mkdirRecurse(configDir);

            _user = new VFSDirectoryPackage("user", configDir);
            _root = new VFSDirectoryPackage("root", dirSeparator);
        }
        else version (Windows)
        {
            string configDir = getenv("APPDATA").fromStringz.idup ~ dirSeparator ~ userDirName.capitalize;
            mkdirRecurse(configDir);

            _user = new VFSDirectoryPackage("user", configDir);
            _root = new VFSDirectoryPackage("root", getenv("HOMEDRIVE").fromStringz.idup ~ dirSeparator);
        }
        else
            static assert(false, "VFS: Cannot compile for this operating system");
    }

    /**
    Frees all currently loaded packages.
    */
    void freeAll()
    {
        foreach_reverse (IVFSPackage pck; _packages)
            pck.destroy();

        Qomproc.dprintln("Freed all packages.".tr);
    }

    /**
    Adds a package to the VFS. It can accept QPK archives or directories.
    
    Params:
        path = The real path to the package.
    
    Throws: `VFSException` if something goes wrong during loading.
     */
    void addPackage(string path)
    {
        static immutable string[] reservedNames = ["root", "user", "res", ".", "..", "/"];

        enforce!VFSException(path.exists, "Package '%s' cannot be found.".tr.format(path));

        string name = path.baseName.stripExtension.toLower;
        enforce!VFSException(!reservedNames.canFind(name), "Package cannot be named after reserved word '%s'.".tr
            .format(name));

        enforce!VFSException(name !in _indexForName, "Package '%s' has already been added.".tr.format(name));

        if (path.isFile)
            _packages ~= new VFSQPKPackage(name, path);
        else
            _packages ~= new VFSDirectoryPackage(name, path);

        _indexForName[name] = _packages.length - 1; // @suppress(dscanner.suspicious.length_subtraction)
        Qomproc.dprintfln("Added package '%s'.".tr, path);
    }

    /**
    Removes a package from the VFS.
    
    Params:
        name = The name of the package.
    
    Returns: If the package has been removed.
    */
    bool removePackage(string name)
    {
        size_t index = _indexForName.get(name, size_t.max);
        if (index == size_t.max)
            return false;

        _packages = _packages[0 .. index] ~ _packages[index + 1 .. $];
        _indexForName.remove(name);

        foreach (size_t i, IVFSPackage pck; _packages)
            _indexForName[pck.name] = i;

        return true;
    }

    /**
    Retrieves the package with the given name.
    
    Params:
        name = The name of the package to retrieve.

    Returns: The packages with the given name.
    Throws: `VFSException` if the package is not loaded.
     */
    IVFSPackage getPackage(string name)
    {
        size_t index = _indexForName.get(name, size_t.max);
        enforce!VFSException(index < size_t.max, "Package '%s' does not exist.".tr);

        return _packages[index];
    }

    /**
    Retrieves the file with the given name and mode.

    Params:
        path = The path to the file inside the VFS.
        mode = How to open the file, given as a `fopen` compatible string.

    Returns: The file under the given path.
    Throws: `VFSException` if the path is malformed or the file could not be found.
    */
    IVFSFile getFile(string path, string mode = "r")
    {
        Tuple!(string, string, string) splitResult = path.findSplit("://");
        enforce!VFSException(!splitResult[0].empty && !splitResult[1].empty && !splitResult[2].empty,
            "Malformed resource path.".tr);
    	
        // Switch by protocol
        switch (splitResult[0])
        {
            case "res":
                if (splitResult[2].length > 1 && splitResult[2][0] == '/')
                    throw new VFSException("Paths cannot start with an '/'.".tr);
            	
                foreach_reverse (IVFSPackage pck; _packages)
                {
                    try { return pck.getFile(splitResult[2], mode); }
                    catch (VFSException) {}
                }
            	
                throw new VFSException("File '%s' does not exist.".tr.format(path));
            	
            case "root":
                return _root.getFile(splitResult[2], mode);
            	
            case "user":
                return _user.getFile(splitResult[2], mode);
            	
            default:
                throw new VFSException("Unknown VFS protocol '%s'.".tr.format(splitResult[0]));
        }
    }

private static:
    VFSDirectoryPackage _user, _root;
    IVFSPackage[] _packages;
    size_t[string] _indexForName;
}