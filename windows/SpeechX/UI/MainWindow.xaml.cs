using System;
using System.Windows;
using System.Windows.Input;
using SpeechX.Core;

namespace SpeechX.UI
{
    public partial class MainWindow : Window
    {
        private AppState _appState;
        private UpdaterManager _updater;
        
        private HomeControl _homeControl;
        private SettingsControl _settingsControl;

        public MainWindow(AppState appState, UpdaterManager updater)
        {
            InitializeComponent();
            Icon = IconFactory.AppImage();
            _appState = appState;
            _updater = updater;
            
            _homeControl = new HomeControl(_appState);
            _settingsControl = new SettingsControl(_appState, _updater);
            
            _homeControl.RequestOpenSettings += (s, e) => MainContent.Content = _settingsControl;
            _settingsControl.RequestGoHome += (s, e) => MainContent.Content = _homeControl;
            
            MainContent.Content = _homeControl;
        }
        
        private void OnTitleBarDrag(object sender, MouseButtonEventArgs e)
        {
            if (e.LeftButton == MouseButtonState.Pressed)
                DragMove();
        }
        
        private void OnMinimizeClick(object sender, RoutedEventArgs e)
        {
            WindowState = WindowState.Minimized;
        }
        
        private void OnCloseClick(object sender, RoutedEventArgs e)
        {
            Hide();
        }
    }
}

