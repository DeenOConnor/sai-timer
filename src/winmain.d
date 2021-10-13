module winmain;

// By Deen O'Connor

pragma(lib, "user32");

// Standard library imports
import std.stdio;
import std.conv;
import std.datetime.stopwatch;
import std.format;
import std.exception;

// System-based functions imports
import core.thread;
import core.time : dur, Duration;
import core.sys.windows.windows;
import core.sys.windows.winuser;
import core.stdc.stdlib : exit;

// GUI library imports
import dlangui;
import dlangui.platforms.common.platform;
import dlangui.widgets.controls;
import dlangui.widgets.styles : Align;

// Process management and info library
import HackLib;

public static __gshared auto sw = StopWatch(AutoStart.no);

public static __gshared bool runFlag = true;
public static __gshared bool isLookupThreadActive = false;
public static __gshared bool shutdown = false;

public static __gshared GameProcess sai;

public static __gshared TextWidget timerText;
public static __gshared TextWidget errorText;
public static __gshared TextWidget textText;

public static __gshared SwitchButton btnStartStop;
public static __gshared Button btnReset;

Thread timerThread;

mixin APP_ENTRY_POINT;

extern (C) int UIAppMain(string[] args) {
    timerThread = new Thread(&threadedFunction);
    Thread monitorThread = new Thread({
        monitor();
    });

    Window window = Platform.instance.createWindow("SAI Timer", null, 0, 225, 160);
    window.backgroundColor(15790320);

    // UI components initialization and placement
    auto vLayout = new VerticalLayout();
    vLayout.margins(10);
    vLayout.margins(15);
    vLayout.alignment(Align.HCenter);

    auto h1Layout = new HorizontalLayout();
    vLayout.addChild(h1Layout);

    textText = new TextWidget();
    textText.text("SAI Active: ");
    textText.textColor("black");
    textText.fontSize(20);
    textText.fontWeight(600);
    textText.fontFace("Arial");
    h1Layout.addChild(textText);

    timerText = new TextWidget();
    timerText.text("00:00:00");
    timerText.textColor("black");
    timerText.fontSize(20);
    timerText.fontWeight(600);
    timerText.fontFace("Arial");
    h1Layout.addChild(timerText);

    auto h2Layout = new HorizontalLayout();
    h2Layout.margins(5);
    vLayout.addChild(h2Layout);

    btnStartStop = new SwitchButton();
    btnStartStop.enabled(false);
    h2Layout.addChild(btnStartStop);

    btnReset = new Button();
    btnReset.text("Reset");
    btnReset.enabled(false);
    h2Layout.addChild(btnReset);

    auto h3Layout = new HorizontalLayout();
    vLayout.addChild(h3Layout);

    auto h4Layout = new HorizontalLayout();
    h4Layout.margins(Rect(0, 40, 0, 0));
    vLayout.addChild(h4Layout);

    errorText = new TextWidget();
    errorText.text("No errors");
    errorText.textColor("black");
    errorText.fontSize(16);
    errorText.fontWeight(600);
    errorText.fontFace("Arial");
    h4Layout.addChild(errorText);

    // Button logic
    auto startClick = function(Widget w) {
        if (!timerThread.isRunning()) {
            if (sw.running()) {
                sw.stop();
            }
            try {
                runFlag = true;
                timerThread.start();
            } catch (Exception ex) {
                errorText.text(to!dstring(ex.msg));
            }
        }
    };

    auto stopClick = function(Widget w) {
        if (timerThread.isRunning()) {
            if (sw.running()) {
                sw.stop();
            }

            runFlag = false;
            timerThread.join();
            if (timerThread.isRunning) {
                writeln("WTF, finished thread is running!");
            }
        }
    };

    btnStartStop.click = delegate(Widget w) {
        if (w.checked) {
            startClick(w);
        } else {
            stopClick(w);
        }

        return true;
    };

    btnReset.click = delegate(Widget w) {
        if (sw.running()) {
            sw.stop();
        }
        sw.reset();
        timerText.text(to!dstring("00:00:00"));

        return true;
    };

    window.onClose = delegate() {
        shutdown = true;
        runFlag = false;
        isLookupThreadActive = true;
        if (timerThread.isRunning()) {
            timerThread.join();
        }
        if (monitorThread.isRunning()) {
            monitorThread.join();
        }
        Thread.sleep(dur!"seconds"(1));
        exit(0);
    };

    window.mainWidget = vLayout;
    window.show();

    // Code that looks for either SAI or SAI2 to appear
    new Thread({
        lookForSai();
    }).start();

    // Starting monitoring thread, in case SAI exits or crashes it will look for it again
    monitorThread.start();

    return Platform.instance.enterMessageLoop();
}

void threadedFunction() {
    // Preparing variables here to not waste time to allocate new ones each iteration
    HWND fgWnd = null;
    uint pid = 0, tid = 0;

    while(runFlag) {
        // A very strange decision to make some results to be returned and some written to a pointer
        fgWnd = GetForegroundWindow();
        tid = GetWindowThreadProcessId(fgWnd, &pid);

        // If the foreground window owner has the same IDs as SAI this means that SAI is active
        if (pid == sai.processId && tid == sai.threadId) {
            if (!sw.running()) {
                sw.start();
            }
        } else {
            // If foreground window is something else, we update the timer to display new total time
            if (sw.running()) {
                sw.stop();
            }
        }

        auto time = sw.peek().total!"seconds";
        long seconds = time % 60;
        long mints = time / 60;
        long hours = mints / 60;
        long minutes = mints % 60;

        auto timeStr = format!"%02d:%02d:%02d"d(hours, minutes, seconds);

        timerText.text(timeStr);

        // To prevent data corruption it might be a good idea to zero out variables before next use
        fgWnd = null;
        pid = 0;
        tid = 0;

        // This reduces speed, while also reducing the amount of winapi calls
        Thread.sleep(dur!"msecs"(5));
    }
}

void lookForSai() {
    if (!isLookupThreadActive) {
        isLookupThreadActive = true;
        sai = findSai();
        btnStartStop.enabled(true);
        btnReset.enabled(true);
        isLookupThreadActive = false;
    }
}

// Threaded subroutine that performs a simultaneous search for all supported programs
GameProcess findSai() {
    GameProcess result;

    // We don't need to do any shenanigans with the memory, so we disregard modules completely
    string[] modules = [""];

    // A complete rethink of the previous code towards a more flexible and "dynamic" approach
    string[string] programs = [
        "sai.exe" : "SAI 1",
        "sai2.exe" : "SAI 2",
        "krita.exe" : "Krita",
        "MediBangPaintPro.exe" : "MediBang",
        "CLIPStudioPaint.exe" : "ClipStudio",
        "blender.exe" : "Blender",
    ];
    Thread[GameProcess] workers;
    foreach (exe, name; programs) {
        GameProcess gp = new GameProcess(exe, "", modules, name);
        Thread findThread = new Thread({
            gp.runOnProcess(false);
        });
        workers[gp] = findThread;
        findThread.start();
    }

    bool foundProgram = false;

    // If one of the threads has finished, it means a supported program executable has been found
    while(true) {
        foreach (obj, worker; workers) {
            if (!worker.isRunning()) {
                foundProgram = true;
                errorText.text("Found "d ~ to!dstring(obj.programName));
                textText.text(to!dstring(obj.programName) ~ " Active: "d);
                result = obj;
                break;
            } else if (shutdown) {
                result = new GameProcess("sai.exe", "", modules);
                obj.forceStop = true;
                worker.join();
                break;
            }
        }

        // In both cases make sure ALL workers are stopped and none are left running in the background
        if (shutdown || foundProgram) {
            foreach (obj, worker; workers) {
                obj.forceStop = true;
                worker.join();
            }
            break;
        }

    }

    return result;
}

// Monitoring subroutine that checks the presence of the process
void monitor() {
    uint exitCode = 0;
    while(!shutdown) {

        if (isLookupThreadActive) {
            // If a thread is already looking for a process, we want to let it run
            Thread.sleep(dur!"msecs"(15));
            continue;
        }

        if (sai.processHandle !is null) {
            // The trick here is to check the exit code, if process hasn't exited it will be 0x103
            int result = GetExitCodeProcess(sai.processHandle, &exitCode);

            if (result == 0) {
                int errCode = GetLastError();
                string reportText = format!"Error 0x%s in GetExitCodeProcess"(to!string(errCode, 16));
                errorText.text(to!dstring(reportText));
            } else {
                // STILL_ACTIVE code, it means that the process hasn't yet completed
                if (exitCode != 0x103) {
                    // Buttons are blocked because we don't need unnecessary input
                    errorText.text(to!dstring(sai.programName) ~ " process dead"d);
                    if (sw.running()){
                        sw.stop();
                    }
                    //However, we don't want to terminate the timer thread, because it has to react to new data
                    btnStartStop.enabled(false);
                    btnReset.enabled(false);

                    // Launching the same thread template to find new SAI window
                    if (!isLookupThreadActive) {
                        Thread lookupThread = new Thread({
                            lookForSai();
                        });
                        lookupThread.start();
                        lookupThread.join();

                    }
                }
            }
            exitCode = 0;
        }
        Thread.sleep(dur!"msecs"(15));
    }
}
