# sai-timer
A small and simple program to measure time spent in SAI, SAI2, Krita, ClipStudio or MediBangPaintPro.

This was made on request, updated on request, and i'm still not planning on updating this unless there's a bug/feature i'm explicitly asked to deal with, or a random event that will attract significant amounts of people to this program. In case of that, i'll probably bother myself with adding some cosmetic features and maybe properly design the UI.


# Build
I built this with DUB, but you are free to use any tool you want.

To build this, you need to add DLangUI to your project.

You can do this in dub.json by pasting the following line in your "dependencies" section:

`"dlangui": "~>0.9.186"`

MAJOR NOTICE: for a while i kept using DMD 2.090.0 as my dub compiler. Recently i updated it to 2.097.2 and for some reason DLangUI isn't compiling anymore. It just gives you a shit ton of deprecation errors and then fails. So, if any single person in this universe really wants to compile this mess, and you fail, try older compiler versions.
