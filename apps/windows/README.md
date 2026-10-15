# MeteEdit for Windows

Planned. Native Windows app: C#, .NET 10, WPF with the Fluent theme, TagLib# for audio, MP4 and image tags,
Windows Property System for file properties. Minimum Windows 10.

Layout when it lands:

```
MeteEdit.sln
MeteEdit.Core/      providers and field model, portable, builds and tests on any OS
MeteEdit.Core.Tests/
MeteEdit.Wpf/       UI, Windows only
```

Build: `dotnet publish MeteEdit.Wpf -c Release -r win-x64 --self-contained` on Windows. The core library and
its tests run with `dotnet test` on macOS and Linux as well.
