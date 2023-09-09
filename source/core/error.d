module qrescent.core.error;

import std.stdio : stderr;

version (linux)
{
    import std.process : execute, executeShell;

    void showFatalError(string message, string details, string title)
    {
        stderr.writeln(message);

        if (executeShell("type kdialog").status == 0)
            showKDialog(message, details, title);
        else if (executeShell("type zenity").status == 0)
            showZenity(message ~ "\n\n" ~ details, title);
        else
            showXMessage(message ~ "\n\n" ~ details);
    }

private:
    void showKDialog(string message, string details, string title)
    {
        string[5] args;
        args[0] = "kdialog";
        args[1] = "--detailederror";
        args[2] = message;
        args[3] = details;
        args[4] = "--title=" ~ title;

        execute(args);
    }

    void showZenity(string message, string title)
    {
        string[5] args;
        args[0] = "zenity";
        args[1] = "--error";
        args[2] = "--text=" ~ message;
        args[3] = "--title=" ~ title;
        args[4] = "--width=500";

        execute(args);
    }

    void showXMessage(string message)
    {
        string[3] args;
        args[0] = "xmessage";
        args[1] = "-center";
        args[2] = message;

        execute(args);
    }
}
else
{

}