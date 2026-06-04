# Current Windows Native Adapter Map

Status: scaffold.

The active Windows app shell is:

```text
apps/windows/MakelabWinUI
```

The future Windows adapter home is:

```text
src/platforms/windows
```

## Current App Shell Scaffold

```text
apps/windows/MakelabWinUI/App.xaml
apps/windows/MakelabWinUI/MainWindow.xaml
apps/windows/MakelabWinUI/MainWindow.xaml.cs
apps/windows/MakelabWinUI/ViewModels/EditorViewModel.cs
apps/windows/MakelabWinUI/Services/WorkspaceService.cs
```

## Adapter Rule

The Windows native adapter may execute Core contracts with WinUI, Direct3D, Direct2D, Media Foundation, and native export surfaces. It must not define independent FX names, timeline meaning, animation behavior, sample-planner semantics, or export semantics.
