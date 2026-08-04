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
                    $"Morning, {name}. Ready when you are.",
                    "Good morning — let's turn your thoughts into words.",
                    "Morning. Let's get to it."
                });
            }
            else if (hour >= 12 && hour < 17)
            {
                options.AddRange(new[] {
                    $"Back again, {name}? Let's keep talking.",
                    "Afternoon — say what's on your mind.",
                    "Good afternoon. Ready to dictate?"
                });
            }
            else if (hour >= 17 && hour < 22)
            {
                options.AddRange(new[] {
                    $"Evening, {name}. Still have things to say?",
                    "Good evening. Let's get your words down.",
                    "Evening. Keep the ideas flowing."
                });
            }
            else
            {
                options.AddRange(new[] {
                    "Up late? Your voice is faster than your fingers right now.",
                    $"Late night, {name}? Speak your mind.",
                    "Still working? Let's talk it out."
                });
            }
            
            options.AddRange(new[] {
                $"Hey {name}, speak your mind.",
                $"{name}, let's get your words down.",
                $"Talk it out, {name}.",
                "Ready to dictate?",
                "Your voice is your best tool."
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


