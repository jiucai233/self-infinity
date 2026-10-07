/// The client-side view of `docs/api-contract.md`: one method per endpoint.
library;

import 'models.dart';

/// Everything the UI can ask of the backend.
///
/// Two implementations exist:
/// * `HttpApi` (`http_api.dart`) talks to the FastAPI backend.
/// * `FakeApiClient` (`fake_api.dart`) is an in-memory stand-in that follows
///   the offline demo script (contract Section 4); it needs no backend.
///
/// Screens get the instance with `context.read<SelfInfinityApi>()`.
///
/// **Errors.** Every method throws [ApiException] (never anything else) when
/// the call fails: non-2xx → `statusCode` set; no response → `statusCode`
/// null. Show `error.userMessage`, never the raw message.
///
/// **LLM.** GET endpoints never call the LLM. POST endpoints marked (LLM) may
/// take several seconds — show a loading state — and may fail with 502.
///
/// Paths below are relative to the base URL (`http://127.0.0.1:8000/api`).
abstract class SelfInfinityApi {
  /// `POST /skills/generate` (LLM). Body: [GenerateRequest.toJson].
  ///
  /// Not used by the app (courses are made in the chat); kept for seeding
  /// tests. Creates a course. Only the root node is `available`; all others are
  /// `locked`. 422 on invalid settings, 502 on generation failure.
  Future<CourseMap> generateCourse(GenerateRequest request);

  /// `POST /skills/scout` (LLM). The tutorial's first course, read next to the
  /// player's main quests and profile before anything is built: a clear
  /// answer comes back as a tidy title, a vague one ("idk") as up to three
  /// courses to pick from. Never 502: a scout that cannot run answers `clear`
  /// with [answer]. 422 when blank or over 120 characters.
  Future<CourseScout> scoutCourse(String answer);

  /// `GET /courses` — all courses, newest first.
  Future<List<Course>> listCourses();

  /// `GET /courses/{courseId}/map` — the course with all its nodes (ordered by
  /// id) and all contains/requires edges. 404 if the course does not exist.
  Future<CourseMap> getCourseMap(int courseId);

  /// `GET /skills?course_id={courseId}` — nodes ordered by id. Without
  /// [courseId]: the nodes of all courses.
  Future<List<SkillNode>> listSkills({int? courseId});

  /// `POST /skills/{skillId}/audits`. Body `{"mode"}`.
  ///
  /// Starts an audit (an audit). [mode] is `'day'` or `'night'` (night doubles the
  /// turn limit); anything else is a 422. Allowed on `available` and
  /// `mastered` nodes; 400 `skill is locked`, 404 `skill not found`.
  Future<AuditStart> startAudit(int skillId, {String mode = 'day'});

  /// `POST /audits/{sessionId}/turns` (LLM). Body `{"content"}`.
  ///
  /// Returns a [ProbeResult] (another question — a Challenger overturn looks
  /// the same) or a [VerdictResult]. 400 `audit session is already closed`,
  /// 404 `audit session not found`, 502 `The auditor is temporarily
  /// unavailable...` (the user's text should stay in the input for a retry).
  Future<TurnResult> submitTurn(int sessionId, String content);

  /// `POST /audits/{sessionId}/reflection` (LLM). Body `{"reflection"}`.
  ///
  /// Turns a failed audit plus the user's reflection into a lesson card
  /// ([Principle]). 400 if the audit did not fail or already has a card.
  Future<Principle> submitReflection(int sessionId, String reflection);

  /// `GET /narrator/briefing` — the facts behind the left panel (bars) computed
  /// fresh, plus the cached narrative (unused by the UI).
  Future<Briefing> getBriefing();

  /// `POST /skills/{skillId}/search-plan` (LLM). Body `{"gap"}` or
  /// `{"misconception_id"}`.
  ///
  /// Finds up to three learning materials for one specific gap or for the
  /// misconception of a lesson card. One of [gap] / [misconceptionId] is
  /// required (400 otherwise); 404 for an unknown skill or misconception.
  Future<SearchPlan> createSearchPlan(int skillId, {String? gap, int? misconceptionId});

  // -- stage UI (contract Section 5) ------------------------------------------

  /// `POST /chat` (LLM) — one chat message to the front desk. Returns the
  /// saved user message followed by 1–2 assistant messages (the second one
  /// carries the result of the intent that ran). A failing pipeline is
  /// explained in a message (still 200); a failing front desk is a 502.
  ///
  /// [uploadIds] (from [uploadFile]) make a `generate_course` / `none` intent
  /// build the course from those files; an unknown id is a 404
  /// `upload not found` and nothing is saved.
  ///
  /// With [reflectionPrompt] (one of the seven prompts of contract Section 6)
  /// the message is the answer to that prompt and **no LLM runs**: the answer
  /// is written to the journal and the result is three messages — the Guide's
  /// prompt, the user's answer and `Noted. It's in your journal.`. Any other
  /// prompt is a 422.
  ///
  /// With [courseTopic] (the tutorial) a course on that topic is built right
  /// away and **no front desk runs**, so the result does not depend on how it
  /// would classify the message: `[user, "I'll build a world for …", result]`.
  /// It may be blank when [uploadIds] are given (the topic is then the first
  /// file's name); blank without files is a 422.
  Future<List<ChatMessage>> sendChat(
    String message, {
    List<int> uploadIds = const [],
    String? reflectionPrompt,
    String? courseTopic,
  });

  /// `GET /chat/history?limit=` — the last [limit] (1–200) messages, oldest
  /// first.
  Future<List<ChatMessage>> getChatHistory({int limit = 50});

  /// `GET /chat/suggestions` — at most two suggestion lines: how was today (or,
  /// once checked in, the reflection prompt of this time window, flagged
  /// `reflection`), and "continue learning" (a node with `skillId`, or
  /// `message == ""` which only focuses the input).
  Future<List<ChatSuggestion>> getChatSuggestions();

  /// `GET /checkins/today` — today's (KST) check-in, or `null`.
  Future<DailyCheckIn?> getTodayCheckIn();

  /// `GET /skills/{skillId}/overview` — node, course, parents, prerequisites,
  /// audit history and found materials. 404 `skill not found`.
  Future<SkillOverview> getSkillOverview(int skillId);

  /// `GET /audits?limit=` — the latest audits of all courses, newest first
  /// ([limit] 1–100).
  Future<List<AuditSummary>> listAudits({int limit = 20});

  /// `POST /uploads` (multipart, no LLM) — stores a PDF / TXT / MD file (at most
  /// 4 MB) and returns its id for [sendChat]. 400 `Only PDF, TXT or MD files up
  /// to 4 MB.` / `No text could be read from this file.`
  Future<UploadedFile> uploadFile({required String filename, required List<int> bytes});

  // -- life as a game (contract Section 6, endpoints 16 and 25–27) -------------

  /// `GET /plan/current` — the latest study plan (today's quests), or `null`.
  Future<StudyPlan?> getCurrentPlan();

  /// `GET /profile` — the character sheet (empty strings and no rules on a
  /// fresh database).
  Future<Profile> getProfile();

  /// `PUT /profile` — saves the given fields and keeps the others. `identity`,
  /// `vision` and `anti_vision` are at most 280 characters; [rules] at most 5
  /// items of at most 120 characters (blank ones are dropped). Anything over a
  /// limit is a 422. [onboarded] `true` marks the first-run tutorial as done,
  /// `false` shows it again. Returns the saved [Profile].
  Future<Profile> updateProfile({
    String? identity,
    String? vision,
    String? antiVision,
    List<String>? rules,
    bool? onboarded,
  });

  /// `GET /journal?limit=` — answered reflection prompts, newest first
  /// ([limit] 1–100).
  Future<List<JournalEntry>> listJournal({int limit = 20});

  /// `GET /principles` — every lesson card, newest first.
  Future<List<Principle>> listPrinciples();

  // -- main quests (contract Section 6, endpoints 28–31) -----------------------

  /// `GET /goals` — the main quests, oldest first.
  Future<List<Goal>> listGoals();

  /// `POST /goals` — a new main quest without courses. The title is trimmed;
  /// blank or over [Goal.maxTitleLength] characters is a 422, a fourth goal a
  /// 409 `at most 3 main quests`.
  Future<Goal> createGoal(String title);

  /// `PUT /goals/{goalId}` — renames and/or sets the courses of a goal (the
  /// other field is kept). Attaching a course detaches it from any other goal.
  /// 404 `goal not found` / `course not found`.
  Future<Goal> updateGoal(int goalId, {String? title, List<int>? courseIds});

  /// `DELETE /goals/{goalId}` — its courses become side quests. 404 `goal not
  /// found`.
  Future<void> deleteGoal(int goalId);

  /// `DELETE /courses/{id}?delete_nodes=` (no LLM). Deletes a course; it
  /// leaves its main quest and the study plan either way. Without
  /// [deleteNodes] its nodes, audits and lesson cards are kept (hidden with
  /// the course; the lessons still show). With it they are deleted too. 404
  /// for an unknown or already deleted course.
  Future<void> deleteCourse(int courseId, {bool deleteNodes = false});
}
