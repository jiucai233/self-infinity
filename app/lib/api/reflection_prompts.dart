/// The seven reflection prompts of the day (`docs/api-contract.md` Section 6).
///
/// The server picks the prompt of the current KST time window and sends it as
/// the first suggestion; the client only needs the list to mimic that in the
/// fake backend and to check a `reflection_prompt` it is given.
library;

/// One time window of the day (KST wall clock) and its prompt.
class ReflectionWindow {
  const ReflectionWindow(this.fromMinute, this.prompt);

  /// Minutes after midnight (KST) at which the window starts.
  final int fromMinute;
  final String prompt;
}

/// The windows, in clock order; the last one wraps around midnight
/// (21:00–02:59).
const List<ReflectionWindow> reflectionWindows = [
  ReflectionWindow(3 * 60, 'Who are you becoming this week? One sentence.'),
  ReflectionWindow(11 * 60, 'What are you putting off right now?'),
  ReflectionWindow(13 * 60 + 30, 'Looking at the last two hours, what were you really after?'),
  ReflectionWindow(15 * 60 + 15, 'Is today pulling you toward your vision or your anti-vision?'),
  ReflectionWindow(17 * 60, "What matters most that you've been ignoring?"),
  ReflectionWindow(
    19 * 60 + 30,
    'Today, were you guarding an image of yourself or going after what you want?',
  ),
  ReflectionWindow(21 * 60, 'When did you feel most alive today, and when least?'),
];

/// All seven prompts.
List<String> get reflectionPrompts => [for (final w in reflectionWindows) w.prompt];

/// The prompt of the window that contains [minuteOfDay] (minutes after
/// midnight, KST).
String reflectionPromptAt(int minuteOfDay) {
  var prompt = reflectionWindows.last.prompt; // 00:00–02:59 belongs to the night window
  for (final w in reflectionWindows) {
    if (minuteOfDay >= w.fromMinute) prompt = w.prompt;
  }
  return prompt;
}
