# sai-timer
A small and simple program to measure time spent in SAI, SAI2, Krita, ClipStudio, MediBangPaintPro or Blender.

This was made on request, updated on request, and i'm currently very lazily working on adding new features and supporting more programs.


# Build
I built this with DUB, but you are free to use any tool you want.

To build this, you need to add DLangUI to your project.

You can do this in dub.json by pasting the following line in your "dependencies" section:

`"dlangui": "~>0.9.186"`

MAJOR NOTICE: for a while i kept using DMD 2.090.0 as my main compiler. The library, DLangUI, has last been updated in 2017, and now newer compiler versions refuse to compile it because of a ton of deprecated features used. If somehow you wish to compile the project yourself, consider using older compiler versions.
