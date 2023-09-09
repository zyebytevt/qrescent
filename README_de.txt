Das hier ist meine Abgabe für die Physikengine. Da sie vermutlich etwas fetter ist im Vergleich zu anderen, schreibe ich
hier nur mal die wichtigsten Sachen auf.

Um das Programm auszuführen, führe einfach "run.sh" aus. Da ZIP allerdings keine ext4 Permissions mitspeichert, ist
es vielleicht notwendig "run.sh" und "qphysics" ausführbar zu machen. Einfach mit "chmod +x <datei>" oder über die GUI.

Dateien des Archivs
===================

Kurze Erklärung der Dateien der Abgabe:

- libglfw.so.3.2 - Mitgelieferte GLFW Library
- libsndfile.so.1.0.28 - Mitgelieferte SNDFILE Library
- qphysics - Das Spiel selbst
- qphysics.qpk - Qrescent Package für Inhalte des Spiels
- qrescent.qpk - Qrescent Package für Inhalte der Engine
- tools/fntcompile - Programm zum Kompilieren von Qrescent Fonts
- tools/qpklink - Programm zum Kompilieren von Qrescent Packages

Eine Qrescent Package ist ein selbst kreiertes Dateiformat, welches notwendig wurde da TAR und andere nicht komprimierte
Archive es nicht leicht zugelassen haben, dass man davon streamte. Zudem konnte ich bei QPKs unnötigen Stuff wie
Permissions oder Dateiattribute etc. entfernen.
qpklink bietet derweil noch nicht an, QPKs wieder zu entpacken, falls aber Interesse beim Inhalt dieser QPKs besteht,
kann ich sie gerne nachschicken.

Troubleshooting
===============

Falls aus irgendeinem Grund das Spiel nicht starten sollte, könnte es an den Libraries liegen. Ich hoffe zwar es passiert
nicht, aber falls doch, könnte folgender Befehl auf Debian basierten Systemen das Problem beheben:

sudo apt install libglfw3 libsndfile1

Die einzigen Dependencies die Qrescent hat sind GLFW, SNDFILE, OpenGL und OpenAL. Aktuelle Grafiktreiber, die oben
genannten Libraries und einen guten Audiotreiber sollten alle Probleme beheben.

Source Code
===========

Es wurde nur der Source Code der Engine mitgeliefert, da nur dieser relevanten Code für die Physics Engine beinhaltet.
Bei Interesse an anderen Code kann ich gerne nachschicken.

Die Struktur des Codes ist wie folgt:
	qrescent - Root
	├─── components - Implementiert alle Components der Engine
	├─── core - Low-level Code
	│    ├─── qomproc - Implementierung des Qrescent Command Processors
	│    ├─── servers - "Server" sind sowas wie Schnittstellen zwischen high- und low-level
	│    │    ├─── audio
	│    │    ├─── graphics
	│    │    └─── physics3d
	│    └─── vfs - Implementierung des Virtual File Systems
	├─── ecs - Implementierung des Entity-Component-System Systems. Ist Teil von EntitySysD geschrieben von Claude Merle.
	├─── resources - Ressourcen die während der Laufzeit geladen, gecached und wieder gefreed werden können.
	└─── systems - Implementiert alle Systems der Engine

Die wichtigen Dateien hier sind
- qrescent/core/servers/physics3d/package.d
- qrescent/core/servers/physics3d/shapes.d
- qrescent/components/physics.d
- qrescent/systems/physics3d.d
