using System;
using System.Windows;
using System.Windows.Controls;
using SpeechX.Core;

namespace SpeechX.UI
{
    public partial class HomeControl : System.Windows.Controls.UserControl
    {
        private AppState _appState;
        
        public event EventHandler? RequestOpenSettings;
        
        public HomeControl(AppState appState)
        {
            InitializeComponent();
            _appState = appState;
            
            WelcomeText.Text = $"Welcome back, {Environment.UserName}";
            VersionText.Text = $"Version {System.Reflection.Assembly.GetExecutingAssembly().GetName().Version?.ToString(2)}";
            
            _appState.PropertyChanged += (s, e) => {
                if (e.PropertyName == nameof(AppState.TranscriptHistory))
                {
                    UpdateHistory();
                }
            };
            
            UpdateStats();
            UpdateHistory();
        }
        
        private void UpdateStats()
        {
            TotalWordsText.Text = _appState.TotalWordsDictated.ToString();
            StreakText.Text = _appState.CurrentStreakDays.ToString() + " days";
            WpmText.Text = _appState.AverageWPM.ToString();
        }
        
        private void UpdateHistory()
        {
            if (_appState.TranscriptHistory.Count == 0)
            {
                EmptyHistoryText.Visibility = Visibility.Visible;
                HistoryList.Visibility = Visibility.Collapsed;
            }
            else
            {
                EmptyHistoryText.Visibility = Visibility.Collapsed;
                HistoryList.Visibility = Visibility.Visible;
                HistoryList.ItemsSource = null;
                HistoryList.ItemsSource = _appState.TranscriptHistory;
            }
            UpdateStats();
        }
        
        private void OnSettingsClick(object sender, RoutedEventArgs e)
        {
            RequestOpenSettings?.Invoke(this, EventArgs.Empty);
        }
    }
}

