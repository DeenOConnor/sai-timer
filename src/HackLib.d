module HackLib;

// By Deen O'Connor

pragma(lib, "advapi32");
pragma(lib, "psapi");
pragma(lib, "user32");

import core.sys.windows.windows;
import core.sys.windows.winbase;
import core.sys.windows.tlhelp32;
import core.sys.windows.psapi;
import core.stdc.string;
import std.string;
import std.conv;
import std.stdio;
import std.regex;
import core.thread;
import core.time : dur;

class GameProcess {

    PROCESSENTRY32 gameProcess;
    HANDLE processHandle = null;
    HWND gameWindow = null;
    ubyte*[string] processModules;
    uint processId = 0;
    uint threadId = 0;

    bool forceStop = false;

    private wstring targetProcessName;
    private wstring targetWindowName;

    public string programName = "";

    this(string targetProcName, string targetWindName, string[] modules, string name = "") {
        this.targetProcessName = wtext(targetProcName); 
        this.targetWindowName = wtext(targetWindName);
        this.programName = name;

        // Creating entries for all the modules we want to find in the process
        foreach (string mod; modules) { 
            if (mod != "") {
                processModules[mod] = null;
            }
        }
    }

    private uint findProcessByName(wstring procName, PROCESSENTRY32 pEntry) {
        PROCESSENTRY32 procEntry;
        procEntry.dwSize = PROCESSENTRY32.sizeof;

        HANDLE hSnapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
        if (hSnapshot == INVALID_HANDLE_VALUE) {
            int code = GetLastError();
            if (code == 5) {
                writeln("System reported NotEnoughPrivileges, please run the hack as administrator!");
                readln();
            }
            return 0;
        }

        if (!Process32First(hSnapshot, &procEntry)) {
            CloseHandle(hSnapshot);
            return 0;
        }

        do {
            wstring exeFile = "";
            foreach (wchar single; procEntry.szExeFile) { 
                if (single != 0) {
                    exeFile ~= single;
                } else break;
            }
            if (procName == exeFile) {
                this.gameProcess = procEntry;
                if (this.gameProcess.th32ProcessID == 0) {
                    memcpy(&this.gameProcess, &procEntry, PROCESSENTRY32.sizeof); 
                }
                CloseHandle(hSnapshot);
                uint pid = procEntry.th32ProcessID;
                this.processId = pid;
                writeln("Game PID is " ~ text(pid));
                return pid;
            }
        }  while (Process32Next(hSnapshot, &procEntry));

        CloseHandle(hSnapshot);
        return 0;
    }

    private static wstring findProcessNameByRegex(wstring regexp) {
        PROCESSENTRY32 procEntry;
        procEntry.dwSize = PROCESSENTRY32.sizeof;

        HANDLE hSnapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
        if (hSnapshot == INVALID_HANDLE_VALUE) {
            int code = GetLastError();
            if (code == 5) {
                writeln("System reported NotEnoughPrivileges, please run the hack as administrator!");
                readln();
            }
            return ""w;
        }

        if (!Process32First(hSnapshot, &procEntry)) {
            CloseHandle(hSnapshot);
            return ""w;
        }

        do {
            wstring exeFile = ""w;
            foreach (wchar single; procEntry.szExeFile) { 
                if (single != 0) {
                    exeFile ~= single;
                } else break;
            }
            auto rexp = regex(regexp);
            auto capture = matchFirst(exeFile, rexp);
            if (!capture.empty) {
                return exeFile;
            }
        }  while (Process32Next(hSnapshot, &procEntry));

        CloseHandle(hSnapshot);
        return ""w;
    }

    private uint getThreadByProcess(uint processId) {
        THREADENTRY32 threadEntry;
        threadEntry.dwSize = THREADENTRY32.sizeof;
        HANDLE hSnapshot = CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);

        if (hSnapshot == INVALID_HANDLE_VALUE) {
            int code = GetLastError();
            if (code == 5) {
                writeln("System reported NotEnoughPrivileges, please run the hack as administrator!");
                readln();
            }
            return 0;
        }

        if (!Thread32First(hSnapshot, &threadEntry)) {
            CloseHandle(hSnapshot);
            return 0;
        }

        do {
            if (threadEntry.th32OwnerProcessID == processId) {
                CloseHandle(hSnapshot);
                this.threadId = threadEntry.th32ThreadID;
                return threadEntry.th32ThreadID;
            }
        } while (Thread32Next(hSnapshot, &threadEntry));
        CloseHandle(hSnapshot);
        return 0;
    }

    private ubyte* getModuleNamePointer(string moduleName, uint processId) {
        MODULEENTRY32 lpModuleEntry = { 0 };
        HANDLE hSnapshot = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE, processId);
        if (hSnapshot == INVALID_HANDLE_VALUE) {
            int code = GetLastError();
            if (code == 5) {
                writeln("System reported NotEnoughPrivileges, please run the hack as administrator!");
                readln();
            }
            return null;
        }
        lpModuleEntry.dwSize = lpModuleEntry.sizeof;

        int runModule = Module32First(hSnapshot, &lpModuleEntry);
        while (runModule != 0) {
            wstring modulename = "";
            foreach (wchar single; lpModuleEntry.szModule) {
                if(single != 0) {
                    modulename ~= single;
                } else {
                    break;
                }
            }
            if (modulename == wtext(moduleName)) {
                CloseHandle(hSnapshot);
                return lpModuleEntry.modBaseAddr;
            }
            runModule = Module32Next(hSnapshot, &lpModuleEntry);
        }

        CloseHandle(hSnapshot);
        return null;
    }

    private void setDebugPrivileges() {
        HANDLE procHandle = GetCurrentProcess(), handleToken;
        TOKEN_PRIVILEGES priv;
        LUID luid;
        OpenProcessToken(procHandle, TOKEN_ADJUST_PRIVILEGES, &handleToken);
        wstring wstr = "SeDebugPrivilege"w;
        LookupPrivilegeValue(null, cast(wchar*)&wstr, &luid);
        priv.PrivilegeCount = 1;
        priv.Privileges[0].Luid = luid;
        priv.Privileges[0].Attributes = SE_PRIVILEGE_ENABLED;
        uint rnd = 0;
        if (AdjustTokenPrivileges(handleToken, 0, &priv, 0, null, &rnd) == 0) {
            writeln("Error 0x" ~ to!string(GetLastError(), 16) ~ " in AdjustTokenPrivileges()!");
        }
        CloseHandle(handleToken);
        CloseHandle(procHandle);
    }

    public void updateWindow() {
        gameWindow = FindWindow(null, cast(wchar*)this.targetWindowName.ptr);
        if (cast(uint)gameWindow == 0) {
            writeln("Error 0x" ~ to!string(GetLastError(), 16) ~ " in FindWindowW()!");
        }
    }

    public void runOnProcess(bool needDebug = true, bool nameIsRegex = false) {
        if (needDebug) {
            this.setDebugPrivileges();
        }

        if (nameIsRegex) {
            wstring processName = "";
            do {
                processName = this.findProcessNameByRegex(this.targetProcessName);
                Thread.sleep(dur!"msecs"(30));
            } while (processName == ""w && !this.forceStop);
            this.targetProcessName = processName;
        }

        if (this.findProcessByName(this.targetProcessName, this.gameProcess) == 0) {
            writeln("Waiting for the game to appear...");

            while (this.findProcessByName(this.targetProcessName, this.gameProcess) == 0 && !this.forceStop) {
                Thread.sleep(dur!"msecs"(30));
            }
        }

        while (this.getThreadByProcess(gameProcess.th32ProcessID) == 0 && !this.forceStop) {
            Thread.sleep(dur!"msecs"(30));
        }

        if (this.forceStop) {
            return;
        }

        this.processHandle = OpenProcess(PROCESS_ALL_ACCESS, false, gameProcess.th32ProcessID);

        foreach (string moduleName; this.processModules.byKey()) {
            ubyte* modPtr = null;
            modPtr = this.getModuleNamePointer(moduleName, this.gameProcess.th32ProcessID);
            if (modPtr !is null) {
                this.processModules[moduleName] = modPtr;
                continue;
            }
            this.processModules.remove(moduleName);
        }

        if (this.targetWindowName != "") {
            this.updateWindow();
        }
    }
}
