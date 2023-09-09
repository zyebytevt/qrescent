module qrescent.core.exceptions;

private template ExceptionMixin(string name)
{
    enum ExceptionMixin = `class ` ~ name ~ ` : Exception
    {
        this(string message, string file =__FILE__,
            size_t line = __LINE__, Throwable next = null) pure nothrow @safe
        {
            super(message, file, line, next);
        }
    }`;
}

mixin(ExceptionMixin!"CoreException");
mixin(ExceptionMixin!"GraphicsException");
mixin(ExceptionMixin!"QomprocException");
mixin(ExceptionMixin!"VFSException");
mixin(ExceptionMixin!"SceneException");
mixin(ExceptionMixin!"ECSException");
mixin(ExceptionMixin!"EOFException");
mixin(ExceptionMixin!"AudioException");
mixin(ExceptionMixin!"LanguageException");