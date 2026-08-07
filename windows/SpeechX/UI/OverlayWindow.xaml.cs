using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media.Animation;
using SpeechX.Core;
using Rectangle = System.Windows.Shapes.Rectangle;

namespace SpeechX.UI;

public partial class OverlayWindow : Window
{
    private const int GWL_EXSTYLE = -20;
    private const int WS_EX_NOACTIVATE = 0x08000000;
    private const int WS_EX_TOOLWINDOW = 0x80;

    private readonly AppState _appState;
    private const double MinBar = 6;
    private const double MaxBar = 28;

    public OverlayWindow(AppState appState)
    {
        InitializeComponent();
        _appState = appState;
        _appState.PropertyChanged += OnAppStateChanged;
        _appState.AudioEngine.VolumeChanged += OnVolumeChanged;
    }

    private void OnAppStateChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName != nameof(AppState.LiveTranscript)) return;
        var text = _appState.LiveTranscript;
        TranscriptText.Text = text;
        TranscriptText.Visibility = string.IsNullOrEmpty(text) ? Visibility.Collapsed : Visibility.Visible;
        if (IsVisible) Reposition();
    }

    private void OnVolumeChanged(float rms)
    {
        Dispatcher.InvokeAsync(() =>
        {
            if (!IsVisible) return;
            
            // Map rms (e.g. 0.0 to 0.1) to height
            double normalized = Math.Min(1.0, rms * 10); // scale up
            if (normalized < 0.05) normalized = 0;
            
            double targetHeight = MinBar + (MaxBar - MinBar) * normalized;
            
            Rectangle[] bars = { Bar1, Bar2, Bar3, Bar4 };
            foreach (var bar in bars)
            {
                var anim = new DoubleAnimation(targetHeight, TimeSpan.FromMilliseconds(50));
                bar.BeginAnimation(HeightProperty, anim);
            }
        });
    }

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);
        var hwnd = new WindowInteropHelper(this).Handle;
        int ex = GetWindowLong(hwnd, GWL_EXSTYLE);
        SetWindowLong(hwnd, GWL_EXSTYLE, ex | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW);
    }

    public void ShowOverlay()
    {
        Reposition();
        Opacity = 0;
        Show();
        var fade = new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(200));
        BeginAnimation(OpacityProperty, fade);
    }

    public void HideOverlay()
    {
        var fade = new DoubleAnimation(Opacity, 0, TimeSpan.FromMilliseconds(180));
        fade.Completed += (_, _) => Hide();
        BeginAnimation(OpacityProperty, fade);
    }

    private void Reposition()
    {
        UpdateLayout();
        if (GetCursorPos(out var pt))
        {
            Left = pt.X + 16;
            Top = pt.Y + 16;
            var area = SystemParameters.WorkArea;
            if (Left + ActualWidth > area.Right) Left = area.Right - ActualWidth - 8;
            if (Top + ActualHeight > area.Bottom) Top = area.Bottom - ActualHeight - 8;
        }
        else
        {
            var area = SystemParameters.WorkArea;
            Left = area.Left + (area.Width - ActualWidth) / 2;
            Top = area.Bottom - ActualHeight - 40;
        }
    }

    private void OnCancelClick(object sender, RoutedEventArgs e)
    {
        _appState.HotkeyManager?.CancelRecording();
    }

    private void OnConfirmClick(object sender, RoutedEventArgs e)
    {
        _ = _appState.HotkeyManager?.StopRecordingAndTranscribeAsync();
    }

    protected override void OnClosing(CancelEventArgs e)
    {
        e.Cancel = true;
        HideOverlay();
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct POINT
    {
        public int X;
        public int Y;
    }

    [DllImport("user32.dll")] private static extern bool GetCursorPos(out POINT lpPoint);
    [DllImport("user32.dll")] private static extern int GetWindowLong(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll")] private static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
}
