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
        
                private string GetGreeting()
        {
            int hour = DateTime.Now.Hour;
            string name = Environment.UserName;
            var options = new System.Collections.Generic.List<string>();
            
            if (hour >= 5 && hour < 12)
            {
                options.AddRange(new[] {
                    $"Morning, {name}.",
                    "Good morning � let's turn your thoughts into words.",
                    "Morning. Let's get your thoughts down."
                });
            }
            else if (hour >= 12 && hour < 17)
            {
                options.AddRange(new[] {
                    $"Good afternoon, {name}.",
                    "Afternoon � say what's on your mind.",
                    "Good afternoon. Listening when you are."
                });
            }
            else if (hour >= 17 && hour < 22)
            {
                options.AddRange(new[] {
                    $"Good evening, {name}.",
                    "Evening. Ready to capture.",
                    "Good evening. Let's get your thoughts down."
                });
            }
            else
            {
                options.AddRange(new[] {
                    "Late night, {name}.",
                    $"Ready to capture.",
                    "Listening when you are."
                });
            }
            
            options.AddRange(new[] {
                $"Hello, {name}.",
                $"Ready to dictate.",
                $"Let's get your thoughts down.",
                "Listening when you are.",
                "Ready to capture."
            });
            
            return options[new Random().Next(options.Count)];
        }
        public HomeControl(AppState appState)
        {
            InitializeComponent();
            _appState = appState;
            
            WelcomeText.Text = GetGreeting();
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



