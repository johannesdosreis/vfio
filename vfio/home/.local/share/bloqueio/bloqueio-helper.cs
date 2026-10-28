// Desbloqueia a sessão do console digitando a senha na tela de bloqueio, sem trocar de sessão.
// Compilado e instalado em C:\ProgramData\bloqueio pelo `bloqueio instalar` (no Linux).
//
//   bloqueio-helper.exe unlock   roda como SYSTEM na sessão 0 (tarefa UnlockNow). Se a sessão do
//                                console estiver bloqueada, abre a si mesmo com "type" dentro dela,
//                                ainda como SYSTEM e na área de trabalho segura (winsta0\Winlogon).
//   bloqueio-helper.exe type     levanta a cortina, digita a senha e Enter (SendInput só alcança a
//                                própria sessão, por isso o processo precisa estar na sessão 1).
//   bloqueio-helper.exe screenshot   diagnóstico: salva a tela que está recebendo a entrada (mesmo a
//                                de bloqueio) em C:\ProgramData\bloqueio\tela.png.
//
// A senha é a do auto login, que o Windows guarda no segredo LSA "DefaultPassword" (só o SYSTEM lê).
// O tsdiscon/tscon também desbloqueia, mas troca a sessão do console, e o SunshineService reinicia
// o sunshine.exe a cada troca, derrubando o Moonlight. Digitar a senha não troca nada.
// O log (sem a senha) fica em C:\ProgramData\bloqueio\helper.log.
using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;

static class BloqueioHelper
{
    const string Dir = @"C:\ProgramData\bloqueio";

    static int Main(string[] args)
    {
        string mode = args.Length > 0 ? args[0] : "";
        try
        {
            if (mode == "unlock") return Unlock();
            if (mode == "type") return TypePassword();
            if (mode == "screenshot") return RunInConsole("shot");
            if (mode == "shot") return Shot();
        }
        catch (Exception e)
        {
            Log(mode + ": " + e.Message);
            return 99;
        }
        Console.Error.WriteLine("uso: bloqueio-helper unlock|screenshot");
        return 2;
    }

    static void Log(string msg)
    {
        try
        {
            File.AppendAllText(Path.Combine(Dir, "helper.log"),
                DateTime.Now.ToString("s") + " [sessão " + Process.GetCurrentProcess().SessionId + "] " + msg + "\r\n");
        }
        catch { }
    }

    // O LogonUI só existe enquanto a tela de bloqueio (ou de login) está aberta.
    static bool Locked(uint session)
    {
        return Process.GetProcessesByName("LogonUI").Any(p => p.SessionId == session);
    }

    static int Unlock()
    {
        uint session = WTSGetActiveConsoleSessionId();
        if (session == 0xFFFFFFFF) { Log("nenhuma sessão no console"); return 1; }
        if (!Locked(session)) { Log("sessão " + session + " não está bloqueada, nada a fazer"); return 0; }
        return RunInConsole("type");
    }

    // Abre este exe com `arg` na sessão do console, como SYSTEM, na área de trabalho segura.
    static int RunInConsole(string arg)
    {
        uint session = WTSGetActiveConsoleSessionId();
        if (session == 0xFFFFFFFF) { Log("nenhuma sessão no console"); return 1; }
        // Mudar a sessão de um token exige SeTcbPrivilege, que o SYSTEM tem mas pode estar desligado.
        EnablePrivilege("SeTcbPrivilege");
        IntPtr token, primary;
        if (!OpenProcessToken(GetCurrentProcess(), TOKEN_ALL_ACCESS, out token)) return Fail("OpenProcessToken");
        if (!DuplicateTokenEx(token, TOKEN_ALL_ACCESS, IntPtr.Zero, 2 /* SecurityImpersonation */, 1 /* TokenPrimary */, out primary))
            return Fail("DuplicateTokenEx");
        if (!SetTokenInformation(primary, 12 /* TokenSessionId */, ref session, 4)) return Fail("SetTokenInformation");

        var si = new STARTUPINFO();
        si.cb = Marshal.SizeOf(si);
        si.lpDesktop = @"winsta0\Winlogon";
        PROCESS_INFORMATION pi;
        string exe = Process.GetCurrentProcess().MainModule.FileName;
        if (!CreateProcessAsUser(primary, null, "\"" + exe + "\" " + arg, IntPtr.Zero, IntPtr.Zero, false,
                CREATE_NO_WINDOW, IntPtr.Zero, Dir, ref si, out pi))
            return Fail("CreateProcessAsUser");

        WaitForSingleObject(pi.hProcess, 30000);
        uint code;
        GetExitCodeProcess(pi.hProcess, out code);
        CloseHandle(pi.hThread);
        CloseHandle(pi.hProcess);
        CloseHandle(primary);
        CloseHandle(token);
        Log("sessão " + session + ": " + arg + " saiu com " + code);
        return (int)code;
    }

    static int Shot()
    {
        IntPtr desk = OpenInputDesktop(0, false, GENERIC_ALL);
        if (desk == IntPtr.Zero || !SetThreadDesktop(desk)) return Fail("OpenInputDesktop/SetThreadDesktop");
        int w = GetSystemMetrics(78 /* SM_CXVIRTUALSCREEN */), h = GetSystemMetrics(79 /* SM_CYVIRTUALSCREEN */);
        using (var bmp = new System.Drawing.Bitmap(w, h))
        {
            using (var g = System.Drawing.Graphics.FromImage(bmp))
                g.CopyFromScreen(GetSystemMetrics(76), GetSystemMetrics(77), 0, 0, bmp.Size);
            bmp.Save(Path.Combine(Dir, "tela.png"), System.Drawing.Imaging.ImageFormat.Png);
        }
        return 0;
    }

    static int TypePassword()
    {
        uint session = (uint)Process.GetCurrentProcess().SessionId;
        string password = LsaSecret("DefaultPassword");
        if (string.IsNullOrEmpty(password)) { Log("segredo DefaultPassword vazio ou ausente"); return 3; }

        // 1. Levantar a cortina (relógio e widgets). Ela é o LockApp, na área de trabalho Default;
        //    o campo de senha é o LogonUI, na Winlogon. O espaço chega à cortina, que tem o foco.
        int spaces = 0;
        for (int i = 0; InputDesktopName() != "Winlogon"; i++)
        {
            if (i == 16) { Log("a cortina não levantou (área de trabalho de entrada: " + InputDesktopName() + ")"); return 6; }
            if (i % 4 == 0) { OnInputDesktop(() => Key(VK_SPACE)); spaces++; }
            Thread.Sleep(250);
        }
        Thread.Sleep(500);                     // o campo de senha recebe o foco depois da animação

        // 2. Digitar a senha já na área de trabalho segura.
        uint sent = 0, expected = (uint)(4 + 2 + password.Length * 2 + 2);
        OnInputDesktop(() =>
        {
            sent += Chord(VK_CONTROL, 0x41 /* A */);   // limpa o campo, caso o espaço tenha caído nele
            sent += Key(VK_BACK);
            foreach (char c in password) { sent += Unicode(c); Thread.Sleep(15); }
            sent += Key(VK_RETURN);
        });
        password = null;
        if (sent != expected) Log("o SendInput aceitou " + sent + " de " + expected + " eventos");

        for (int i = 0; i < 40; i++)
        {
            if (!Locked(session)) { Log("desbloqueado (" + spaces + " espaço(s) para levantar a cortina)"); return 0; }
            Thread.Sleep(250);
        }
        Log("senha digitada, mas a sessão continua bloqueada");
        return 4;
    }

    // Nome da área de trabalho que recebe a entrada agora: "Default" com a cortina na frente,
    // "Winlogon" com o campo de senha.
    static string InputDesktopName()
    {
        IntPtr desk = OpenInputDesktop(0, false, 0x0001 /* DESKTOP_READOBJECTS */);
        if (desk == IntPtr.Zero) return "?";
        var buf = new byte[512];
        uint needed;
        string name = GetUserObjectInformation(desk, 2 /* UOI_NAME */, buf, (uint)buf.Length, out needed)
            ? System.Text.Encoding.Unicode.GetString(buf, 0, (int)needed).TrimEnd('\0') : "?";
        CloseDesktop(desk);
        return name;
    }

    // O SendInput só vale numa thread que esteja na área de trabalho de entrada, e ela muda quando a
    // cortina sobe. Uma thread não troca de área de trabalho depois de criar janelas, então cada
    // etapa roda numa thread nova, presa à área de trabalho de entrada daquele momento.
    static void OnInputDesktop(Action action)
    {
        var t = new Thread(() =>
        {
            IntPtr desk = OpenInputDesktop(0, false, GENERIC_ALL);
            if (desk == IntPtr.Zero || !SetThreadDesktop(desk)) { Fail("OpenInputDesktop/SetThreadDesktop"); return; }
            action();
        });
        t.Start();
        t.Join();
    }

    static int Fail(string what)
    {
        Log(what + " falhou: erro " + Marshal.GetLastWin32Error());
        return 5;
    }

    // ---- teclado ----

    const ushort VK_BACK = 0x08, VK_RETURN = 0x0D, VK_CONTROL = 0x11, VK_SPACE = 0x20;
    const uint KEYEVENTF_KEYUP = 0x2, KEYEVENTF_UNICODE = 0x4;

    static uint Send(params INPUT[] inputs)
    {
        return SendInput((uint)inputs.Length, inputs, Marshal.SizeOf(typeof(INPUT)));
    }

    static INPUT Vk(ushort vk, bool up)
    {
        var i = new INPUT { type = 1 };
        i.u.ki.wVk = vk;
        i.u.ki.wScan = (ushort)MapVirtualKey(vk, 0);
        i.u.ki.dwFlags = up ? KEYEVENTF_KEYUP : 0;
        return i;
    }

    static uint Key(ushort vk)
    {
        uint n = Send(Vk(vk, false), Vk(vk, true));
        Thread.Sleep(50);
        return n;
    }

    static uint Chord(ushort mod, ushort vk)
    {
        uint n = Send(Vk(mod, false), Vk(vk, false), Vk(vk, true), Vk(mod, true));
        Thread.Sleep(50);
        return n;
    }

    static uint Unicode(char c)
    {
        var down = new INPUT { type = 1 };
        down.u.ki.wScan = c;
        down.u.ki.dwFlags = KEYEVENTF_UNICODE;
        var up = down;
        up.u.ki.dwFlags = KEYEVENTF_UNICODE | KEYEVENTF_KEYUP;
        return Send(down, up);
    }

    // ---- LSA ----

    static string LsaSecret(string name)
    {
        var attrs = new LSA_OBJECT_ATTRIBUTES();
        attrs.Length = Marshal.SizeOf(attrs);
        IntPtr policy;
        uint status = LsaOpenPolicy(IntPtr.Zero, ref attrs, 0x4 /* POLICY_GET_PRIVATE_INFORMATION */, out policy);
        if (status != 0) { Log("LsaOpenPolicy: erro " + LsaNtStatusToWinError(status)); return null; }
        var key = new LSA_UNICODE_STRING();
        key.Buffer = Marshal.StringToHGlobalUni(name);
        key.Length = (ushort)(name.Length * 2);
        key.MaximumLength = (ushort)(key.Length + 2);
        IntPtr data;
        status = LsaRetrievePrivateData(policy, ref key, out data);
        Marshal.FreeHGlobal(key.Buffer);
        LsaClose(policy);
        if (status != 0) { Log("LsaRetrievePrivateData: erro " + LsaNtStatusToWinError(status)); return null; }
        var secret = (LSA_UNICODE_STRING)Marshal.PtrToStructure(data, typeof(LSA_UNICODE_STRING));
        string value = Marshal.PtrToStringUni(secret.Buffer, secret.Length / 2);
        LsaFreeMemory(data);
        return value;
    }

    static void EnablePrivilege(string name)
    {
        IntPtr token;
        if (!OpenProcessToken(GetCurrentProcess(), TOKEN_ALL_ACCESS, out token)) return;
        var tp = new TOKEN_PRIVILEGES { PrivilegeCount = 1, Attributes = 2 /* SE_PRIVILEGE_ENABLED */ };
        if (LookupPrivilegeValue(null, name, out tp.Luid))
            AdjustTokenPrivileges(token, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
        CloseHandle(token);
    }

    // ---- P/Invoke ----

    const uint TOKEN_ALL_ACCESS = 0xF01FF, GENERIC_ALL = 0x10000000, CREATE_NO_WINDOW = 0x08000000;

    [StructLayout(LayoutKind.Sequential)]
    struct KEYBDINPUT { public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }

    [StructLayout(LayoutKind.Sequential)]
    struct MOUSEINPUT { public int dx; public int dy; public uint mouseData; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }

    // A união tem o tamanho do MOUSEINPUT, o maior membro: o SendInput confere o tamanho do INPUT.
    [StructLayout(LayoutKind.Explicit)]
    struct InputUnion { [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki; }

    [StructLayout(LayoutKind.Sequential)]
    struct INPUT { public uint type; public InputUnion u; }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct STARTUPINFO
    {
        public int cb; public string lpReserved; public string lpDesktop; public string lpTitle;
        public int dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
        public short wShowWindow, cbReserved2; public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct PROCESS_INFORMATION { public IntPtr hProcess, hThread; public int dwProcessId, dwThreadId; }

    [StructLayout(LayoutKind.Sequential)]
    struct LUID { public uint LowPart; public int HighPart; }

    [StructLayout(LayoutKind.Sequential)]
    struct TOKEN_PRIVILEGES { public uint PrivilegeCount; public LUID Luid; public uint Attributes; }

    [StructLayout(LayoutKind.Sequential)]
    struct LSA_UNICODE_STRING { public ushort Length; public ushort MaximumLength; public IntPtr Buffer; }

    [StructLayout(LayoutKind.Sequential)]
    struct LSA_OBJECT_ATTRIBUTES
    {
        public int Length; public IntPtr RootDirectory, ObjectName; public uint Attributes;
        public IntPtr SecurityDescriptor, SecurityQualityOfService;
    }

    [DllImport("kernel32.dll")] static extern uint WTSGetActiveConsoleSessionId();
    [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll")] static extern uint WaitForSingleObject(IntPtr h, uint ms);
    [DllImport("kernel32.dll")] static extern bool GetExitCodeProcess(IntPtr h, out uint code);

    [DllImport("advapi32.dll", SetLastError = true)] static extern bool OpenProcessToken(IntPtr process, uint access, out IntPtr token);
    [DllImport("advapi32.dll", SetLastError = true)]
    static extern bool DuplicateTokenEx(IntPtr token, uint access, IntPtr attrs, int level, int type, out IntPtr newToken);
    [DllImport("advapi32.dll", SetLastError = true)]
    static extern bool SetTokenInformation(IntPtr token, int cls, ref uint value, int length);
    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool LookupPrivilegeValue(string system, string name, out LUID luid);
    [DllImport("advapi32.dll", SetLastError = true)]
    static extern bool AdjustTokenPrivileges(IntPtr token, bool disableAll, ref TOKEN_PRIVILEGES state, int length, IntPtr prev, IntPtr retLength);
    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool CreateProcessAsUser(IntPtr token, string app, string cmdLine, IntPtr procAttrs, IntPtr threadAttrs,
        bool inherit, uint flags, IntPtr env, string cwd, ref STARTUPINFO si, out PROCESS_INFORMATION pi);

    [DllImport("advapi32.dll")] static extern uint LsaOpenPolicy(IntPtr system, ref LSA_OBJECT_ATTRIBUTES attrs, uint access, out IntPtr policy);
    [DllImport("advapi32.dll")] static extern uint LsaRetrievePrivateData(IntPtr policy, ref LSA_UNICODE_STRING key, out IntPtr data);
    [DllImport("advapi32.dll")] static extern uint LsaFreeMemory(IntPtr p);
    [DllImport("advapi32.dll")] static extern uint LsaClose(IntPtr policy);
    [DllImport("advapi32.dll")] static extern int LsaNtStatusToWinError(uint status);

    [DllImport("user32.dll", SetLastError = true)] static extern IntPtr OpenInputDesktop(uint flags, bool inherit, uint access);
    [DllImport("user32.dll", SetLastError = true)] static extern bool SetThreadDesktop(IntPtr desk);
    [DllImport("user32.dll")] static extern uint SendInput(uint count, INPUT[] inputs, int size);
    [DllImport("user32.dll")] static extern uint MapVirtualKey(uint code, uint mapType);
    [DllImport("user32.dll")] static extern int GetSystemMetrics(int index);
    [DllImport("user32.dll")] static extern bool CloseDesktop(IntPtr desk);
    [DllImport("user32.dll", SetLastError = true, EntryPoint = "GetUserObjectInformationW")]
    static extern bool GetUserObjectInformation(IntPtr obj, int index, byte[] info, uint length, out uint needed);
}
