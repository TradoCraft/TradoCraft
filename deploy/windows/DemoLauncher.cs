using System;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Web.Script.Serialization;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Forms;

internal static class DemoLauncher
{
    private static readonly string Bundle = AppDomain.CurrentDomain.BaseDirectory;
    private static readonly string Root = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "TradoCraft", AppDomain.CurrentDomain.SetupInformation.ApplicationName == "Smoke Demo.exe"
            ? "Demo packaging smoke" : "Demo");
    private static readonly string Instance = Path.Combine(Root, "instance");
    private static readonly string Logs = Path.Combine(Root, "logs");
    private static readonly string PgData = Path.Combine(Instance, "postgres");
    private static readonly string Password = Path.Combine(Instance, "db-password");
    private static readonly string ReadyFile = Path.Combine(Root, "api-address");
    private static readonly string Postgres = Path.Combine(Bundle, "postgresql", "bin");
    private static readonly object LogLock = new object();
    private const string Title = "TradoCraft Demo";

    [STAThread]
    private static int Main(string[] args)
    {
        bool smoke = Array.IndexOf(args, "--smoke") >= 0;
        if (smoke && AppDomain.CurrentDomain.SetupInformation.ApplicationName != "Smoke Demo.exe")
            return 1;
        try
        {
            Directory.CreateDirectory(Root);
            RejectReparsePoint(Root);
            Directory.CreateDirectory(Logs);
            FileStream lease;
            try
            {
                lease = File.Open(Path.Combine(Root, "launcher.lock"), FileMode.OpenOrCreate,
                    FileAccess.ReadWrite, FileShare.None);
            }
            catch (IOException ex)
            {
                if ((ex.HResult & 0xffff) != 32) throw;
                if (!smoke) MessageBox.Show("A demo is already running. Switch to its existing window.", Title);
                return smoke ? 1 : 0;
            }
            using (lease)
            {
                if (Directory.Exists(Instance)) RejectReparsePoint(Instance);
                if (Array.IndexOf(args, "--reset") >= 0)
                {
                    if (!smoke && MessageBox.Show("Erase this demo's data and tutorial progress?",
                        Title, MessageBoxButtons.YesNo, MessageBoxIcon.Warning,
                        MessageBoxDefaultButton.Button2) != DialogResult.Yes) return 0;
                    if (Directory.Exists(Instance))
                    {
                        // Move the whole instance out of service so a partial cleanup cannot
                        // leave the active database paired with old files or credentials.
                        string retired = Path.Combine(Root, "reset-" + Guid.NewGuid().ToString("N"));
                        Directory.Move(Instance, retired);
                    }
                    DeleteRetiredInstances();
                    if (smoke) return 0;
                }
                RunDemo(smoke);
            }
            return 0;
        }
        catch (Exception ex)
        {
            try { Log("launcher", ex.ToString()); }
            catch (IOException) { Console.Error.WriteLine(ex.Message); }
            if (!smoke)
                MessageBox.Show(ex.Message + "\n\nLogs: " + Logs, Title,
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }

    private static void RunDemo(bool smoke)
    {
        // PostgreSQL 16's Windows pg_ctl starts the server through cmd.exe.
        if (Bundle.IndexOfAny(new[] { '%', '!' }) >= 0)
            throw new IOException("Extract the demo to a folder without % or ! in its path, such as Documents\\TradoCraft Demo.");
        if (Root.IndexOfAny(new[] { '%', '!' }) >= 0)
            throw new IOException("The demo needs a Windows profile whose Local AppData path does not contain % or !.");

        using (var job = new ProcessJob())
        {
            Initialise(job);
            int port = AvailablePort();
            File.Delete(ReadyFile);
            Process api = null;
            Process worker = null;
            Process flutter = null;
            bool pgStarted = false;
            try
            {
                StartPostgres(job, port);
                pgStarted = true;
                string database = "postgresql://tradocraft_demo:" + File.ReadAllText(Password).Trim()
                    + "@127.0.0.1:" + port + "/postgres";
                var apiSpec = Backend("tradocraft-api", database);
                apiSpec.EnvironmentVariables["BIND_ADDR"] = "127.0.0.1:0";
                apiSpec.EnvironmentVariables["AUTH_MODE"] = "dev";
                apiSpec.EnvironmentVariables["SEED_DEV_DATA"] = "true";
                apiSpec.EnvironmentVariables["TRADOCRAFT_READY_FILE"] = ReadyFile;
                api = Start(job, apiSpec, "api");
                string url = WaitForApi(api);
                worker = Start(job, Backend("tradocraft-worker", database), "worker");

                if (smoke)
                {
                    Smoke(worker, url);
                    return;
                }

                var app = Command(Path.Combine(Bundle, "app", "tradocraft_app.exe"), "--portable-demo");
                app.EnvironmentVariables["TRADOCRAFT_DEMO_URL"] = url;
                app.EnvironmentVariables["TRADOCRAFT_DEMO_PROFILE"] = Path.Combine(Instance, "profile.json");
                flutter = Start(job, app, "flutter");
                while (!flutter.WaitForExit(500))
                {
                    RequireRunning(api, "API");
                    RequireRunning(worker, "Worker");
                }
                if (flutter.ExitCode != 0) throw new Exception("Flutter exited with code " + flutter.ExitCode);
            }
            finally
            {
                Stop(flutter);
                Stop(worker, true);
                Stop(api, true);
                if (pgStarted)
                    Run(job, Path.Combine(Postgres, "pg_ctl.exe"), "launcher", "stop",
                        "-D", PgData, "-w", "-t", "30", "-m", "fast");
            }
        }
    }

    private static void DeleteRetiredInstances()
    {
        foreach (string directory in Directory.GetDirectories(Root, "reset-*"))
        {
            Guid id;
            if (!Guid.TryParseExact(Path.GetFileName(directory).Substring("reset-".Length), "N", out id))
                continue;
            RejectReparsePoint(directory);
            for (int attempt = 0; ; attempt++)
            {
                try
                {
                    Directory.Delete(directory, true);
                    break;
                }
                catch (IOException ex)
                {
                    if (ex is DirectoryNotFoundException && !Directory.Exists(directory)) break;
                    if (attempt == 9) throw;
                }
                catch (UnauthorizedAccessException)
                {
                    if (attempt == 9) throw;
                }
                Thread.Sleep(300);
            }
        }
    }

    private static void StartPostgres(ProcessJob job, int port)
    {
        string pgCtl = Path.Combine(Postgres, "pg_ctl.exe");
        string[] args = { pgCtl, "start", "-D", PgData, "-l", Path.Combine(Logs, "postgres.log"),
            "-w", "-t", "60", "-o", "-h 127.0.0.1 -p " + port };
        // Use a file for pg_ctl diagnostics. Its background server can inherit handles,
        // so waiting for EOF on pg_ctl's redirected pipes can hang after pg_ctl exits.
        string cmd = Path.Combine(Environment.SystemDirectory, "cmd.exe");
        var spec = Command(cmd);
        spec.EnvironmentVariables["COMSPEC"] = cmd;
        spec.RedirectStandardOutput = false;
        spec.RedirectStandardError = false;
        spec.Arguments = "/d /v:off /s /c \"" + String.Join(" ", Array.ConvertAll(args, Quote))
            + " >> " + Quote(Path.Combine(Logs, "pg_ctl.log")) + " 2>&1\"";
        Run(job, spec, "launcher", "pg_ctl.exe start");
    }

    private static void Initialise(ProcessJob job)
    {
        if (Directory.Exists(Instance))
        {
            if (!File.Exists(Password) || !File.Exists(Path.Combine(PgData, "PG_VERSION")))
                throw new Exception("Demo data is incomplete. Run Reset Demo to recreate it.");
            return;
        }

        string staging = Path.Combine(Root, "initialising");
        if (Directory.Exists(staging))
        {
            RejectReparsePoint(staging);
            Directory.Delete(staging, true);
        }
        Directory.CreateDirectory(staging);
        var bytes = new byte[32];
        using (var rng = RandomNumberGenerator.Create()) rng.GetBytes(bytes);
        string password = Path.Combine(staging, "db-password");
        File.WriteAllText(password, BitConverter.ToString(bytes).Replace("-", "") + "\n");
        Run(job, Path.Combine(Postgres, "initdb.exe"), "launcher",
            "-D", Path.Combine(staging, "postgres"), "--username=tradocraft_demo",
            "--auth=scram-sha-256", "--pwfile", password, "--encoding=UTF8", "--locale=C");
        Directory.CreateDirectory(Path.Combine(staging, "files"));
        Directory.CreateDirectory(Path.Combine(staging, "outbox"));
        Directory.Move(staging, Instance);
    }

    private static void RejectReparsePoint(string directory)
    {
        if ((File.GetAttributes(directory) & FileAttributes.ReparsePoint) != 0)
            throw new IOException("A demo data directory points outside the demo: " + directory);
    }

    private static ProcessStartInfo Backend(string name, string database)
    {
        var spec = Command(Path.Combine(Bundle, "backend", name + ".exe"));
        var env = spec.EnvironmentVariables;
        foreach (string key in new[] { "ALLOW_INSECURE_DEV_AUTH", "ALLOW_INSECURE_IDP_URLS",
            "ALLOW_INBOUND_MAIL_IN_NON_LIVE", "CORS_ALLOWED_ORIGINS", "DEV_DEFAULT_USER",
            "EXTRA_SEED_DIR", "BOOTSTRAP_TOKEN", "VIES_URL", "HELPDESK_MAIL_DOMAIN" })
            env.Remove(key);
        env["APP_ENV_KIND"] = "tutorial";
        env["APP_ENV_NAME"] = Title;
        env["DATABASE_URL"] = database;
        env["FILE_STORAGE_DIR"] = Path.Combine(Instance, "files");
        env["TYPST_BIN"] = Path.Combine(Bundle, "typst", "typst.exe");
        env["TEMPLATE_DIR"] = Path.Combine(Bundle, "templates");
        env["MAIL_TRANSPORT"] = "files";
        env["MAIL_FILES_DIR"] = Path.Combine(Instance, "outbox");
        env["POLL_SECONDS"] = "2";
        env["TRADOCRAFT_SHUTDOWN_ON_STDIN"] = "1";
        spec.RedirectStandardInput = true;
        return spec;
    }

    private static int AvailablePort()
    {
        var socket = new TcpListener(IPAddress.Loopback, 0);
        socket.Start();
        try { return ((IPEndPoint)socket.LocalEndpoint).Port; }
        finally { socket.Stop(); }
    }

    private static string WaitForApi(Process api)
    {
        var timeout = Stopwatch.StartNew();
        while (timeout.Elapsed < TimeSpan.FromMinutes(3))
        {
            RequireRunning(api, "API");
            if (File.Exists(ReadyFile))
            {
                string address = File.ReadAllText(ReadyFile).Trim();
                if (Regex.IsMatch(address, @"\A127\.0\.0\.1:[0-9]+\z"))
                {
                    string url = "http://" + address;
                    try
                    {
                        Request(url + "/api/v1/me");
                        return url;
                    }
                    catch (WebException) { }
                }
            }
            Thread.Sleep(250);
        }
        throw new Exception("The demo API did not become ready.");
    }

    private static string Request(string url)
    {
        return Encoding.UTF8.GetString(RequestBytes(url, null));
    }

    private static byte[] RequestBytes(string url, string json)
    {
        var request = (HttpWebRequest)WebRequest.Create(url);
        request.Proxy = null;
        request.AllowAutoRedirect = false;
        request.Timeout = 15000;
        request.ReadWriteTimeout = 15000;
        request.Headers.Add("X-Dev-User", "admin@example.com");
        if (json != null)
        {
            var bytes = Encoding.UTF8.GetBytes(json);
            request.Method = "POST";
            request.ContentType = "application/json";
            request.ContentLength = bytes.Length;
            using (var body = request.GetRequestStream()) body.Write(bytes, 0, bytes.Length);
        }
        using (var response = (HttpWebResponse)request.GetResponse())
        using (var buffer = new MemoryStream())
        {
            response.GetResponseStream().CopyTo(buffer);
            return buffer.ToArray();
        }
    }

    private static void Smoke(Process worker, string url)
    {
        if (!Regex.IsMatch(Request(url + "/api/v1/meta/environment"), @"""kind""\s*:\s*""tutorial"""))
            throw new Exception("Expected a tutorial environment.");
        var serializer = new JavaScriptSerializer();
        var workerStarted = new DateTimeOffset(worker.StartTime.ToUniversalTime());
        var timeout = Stopwatch.StartNew();
        while (true)
        {
            RequireRunning(worker, "Worker");
            var status = serializer.DeserializeObject(Request(url + "/api/v1/admin/worker"))
                as System.Collections.Generic.Dictionary<string, object>;
            DateTimeOffset reportedStart;
            if (Object.Equals(status["state"], "running") &&
                DateTimeOffset.TryParse(status["started_at"] as string, out reportedStart) &&
                reportedStart > workerStarted) break;
            if (timeout.Elapsed > TimeSpan.FromSeconds(30))
                throw new Exception("The demo worker did not report a heartbeat.");
            Thread.Sleep(500);
        }

        string saved = Path.Combine(Instance, "smoke-quotation");
        string id;
        if (File.Exists(saved))
        {
            id = File.ReadAllText(saved).Trim();
        }
        else
        {
            const string body = @"{""customer_id"":""00000000-0000-7000-8000-000000000401"",
                ""lines"":[{""product_id"":""00000000-0000-7000-8000-000000000301"",""quantity"":""1""}]}";
            var quote = serializer.DeserializeObject(Encoding.UTF8.GetString(
                RequestBytes(url + "/api/v1/quotations", body)))
                as System.Collections.Generic.Dictionary<string, object>;
            id = (string)quote["id"];
            File.WriteAllText(saved, id);
        }

        byte[] pdf = RequestBytes(url + "/api/v1/quotations/" + id + "/pdf", null);
        if (pdf.Length < 5 || Encoding.ASCII.GetString(pdf, 0, 5) != "%PDF-")
            throw new Exception("The demo did not generate a quotation PDF.");
    }

    private static ProcessStartInfo Command(string exe, params string[] args)
    {
        var spec = new ProcessStartInfo(exe, String.Join(" ", Array.ConvertAll(args, Quote)));
        spec.WorkingDirectory = Bundle;
        spec.UseShellExecute = false;
        spec.CreateNoWindow = true;
        spec.RedirectStandardOutput = true;
        spec.RedirectStandardError = true;
        foreach (string key in new System.Collections.ArrayList(spec.EnvironmentVariables.Keys))
            if (key.StartsWith("PG", StringComparison.OrdinalIgnoreCase))
                spec.EnvironmentVariables.Remove(key);
        return spec;
    }

    // Quote for the Windows C runtime argument parser, including trailing backslashes.
    private static string Quote(string value)
    {
        return "\"" + Regex.Replace(value, "(\\\\*)(\"|$)", "$1$1$2")
            .Replace("\"", "\\\"") + "\"";
    }

    private static Process Start(ProcessJob job, ProcessStartInfo spec, string log)
    {
        var process = new Process { StartInfo = spec };
        DataReceivedEventHandler write = (s, e) =>
        {
            if (e.Data == null) return;
            try { Log(log, e.Data); }
            catch (IOException) { Debug.WriteLine(e.Data); }
        };
        process.OutputDataReceived += write;
        process.ErrorDataReceived += write;
        process.Start();
        try
        {
            job.Add(process);
            if (spec.RedirectStandardOutput) process.BeginOutputReadLine();
            if (spec.RedirectStandardError) process.BeginErrorReadLine();
            return process;
        }
        catch
        {
            Stop(process);
            throw;
        }
    }

    private static void Run(ProcessJob job, string exe, string log, params string[] args)
    {
        Run(job, Command(exe, args), log, Path.GetFileName(exe));
    }

    private static void Run(ProcessJob job, ProcessStartInfo spec, string log, string name)
    {
        using (var process = Start(job, spec, log))
        {
            if (!process.WaitForExit(90000))
            {
                process.Kill();
                throw new Exception(name + " timed out.");
            }
            if (spec.RedirectStandardOutput || spec.RedirectStandardError) process.WaitForExit();
            if (process.ExitCode != 0)
                throw new Exception(name + " failed with code " + process.ExitCode);
        }
    }

    private static void RequireRunning(Process process, string name)
    {
        if (process.HasExited) throw new Exception(name + " exited with code " + process.ExitCode);
    }

    private static void Stop(Process process, bool graceful = false)
    {
        if (process == null) return;
        using (process)
        {
            if (graceful && !process.HasExited)
            {
                try { process.StandardInput.Close(); }
                catch (IOException) { }
                if (process.WaitForExit(5000)) return;
            }
            if (!process.HasExited)
            {
                try { process.Kill(); }
                catch (InvalidOperationException) { if (!process.HasExited) throw; }
            }
            process.WaitForExit(5000);
        }
    }

    private static void Log(string name, string line)
    {
        lock (LogLock) File.AppendAllText(Path.Combine(Logs, name + ".log"),
            DateTime.Now.ToString("s") + " " + line + Environment.NewLine);
    }
}

// The job handle is private to the launcher. Windows closes it on a forced exit and
// stops any remaining descendants, including the server started by pg_ctl.
internal sealed class ProcessJob : IDisposable
{
    [StructLayout(LayoutKind.Sequential)]
    private struct BasicLimits
    {
        public long PerProcessUserTime, PerJobUserTime;
        public uint Flags;
        public UIntPtr MinimumWorkingSet, MaximumWorkingSet;
        public uint ActiveProcessLimit;
        public UIntPtr Affinity;
        public uint PriorityClass, SchedulingClass;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct ExtendedLimits
    {
        public BasicLimits Basic;
        public ulong ReadOperations, WriteOperations, OtherOperations, ReadBytes, WriteBytes, OtherBytes;
        public UIntPtr ProcessMemoryLimit, JobMemoryLimit, PeakProcessMemory, PeakJobMemory;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr CreateJobObject(IntPtr attributes, IntPtr name);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetInformationJobObject(IntPtr job, int kind, ref ExtendedLimits limits, uint size);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);

    [DllImport("kernel32.dll")]
    private static extern bool CloseHandle(IntPtr handle);

    private readonly IntPtr handle;

    public ProcessJob()
    {
        handle = CreateJobObject(IntPtr.Zero, IntPtr.Zero);
        if (handle == IntPtr.Zero) throw new System.ComponentModel.Win32Exception();
        var limits = new ExtendedLimits { Basic = new BasicLimits { Flags = 0x2000 } };
        if (!SetInformationJobObject(handle, 9, ref limits, (uint)Marshal.SizeOf(limits)))
        {
            var error = new System.ComponentModel.Win32Exception();
            CloseHandle(handle);
            throw error;
        }
    }

    public void Add(Process process)
    {
        if (!AssignProcessToJobObject(handle, process.Handle) && !process.HasExited)
            throw new System.ComponentModel.Win32Exception();
    }

    public void Dispose() { CloseHandle(handle); }
}
