// משותף ל-otzaria.iss ול-otzaria_full.iss. Windows אינו פותח קובץ שנתיבו ארוך מ-259 תווים —
// לא המתקין ולא התוכנה — ולכן אורך תיקיית היעד מוגבל לפי הקובץ בעל הנתיב הארוך ביותר.

#define AppBuildDir AddBackslash(SourcePath) + "..\build\windows\" + AppArch + "\runner\Release"

#define LongestRelPathFrom(int H, str Dir, str Rel) \
  Local[0] = FindGetFileName(H), \
  Local[1] = (Local[0] == "." || Local[0] == "..") ? 0 : \
    DirExists(Dir + "\" + Local[0]) ? LongestRelPath(Dir + "\" + Local[0], Rel + Local[0] + "\") : \
    Len(Rel + Local[0]), \
  Local[2] = FindNext(H) ? LongestRelPathFrom(H, Dir, Rel) : 0, \
  Local[1] > Local[2] ? Local[1] : Local[2]

#define LongestRelPath(str Dir, str Rel) \
  Local[0] = FindFirst(Dir + "\*", faAnyFile), \
  Local[1] = Local[0] ? LongestRelPathFrom(Local[0], Dir, Rel) : 0, \
  Local[0] ? FindClose(Local[0]) : 0, \
  Local[1]

#define MaxInstallDirLength 258 - LongestRelPath(AppBuildDir, "")

function InstallDirTooLong(): Boolean;
begin
  Result := Length(WizardDirValue) > {#MaxInstallDirLength};
  if Result then
    SuppressibleMsgBox('הנתיב של תיקיית ההתקנה ארוך מדי (' + IntToStr(Length(WizardDirValue)) +
      ' תווים), ו-Windows לא יוכל לשמור בה את כל קובצי התוכנה.' + #13#10#13#10 +
      'בחרו תיקייה שהנתיב שלה עד {#MaxInstallDirLength} תווים.', mbError, MB_OK, IDOK);
end;
