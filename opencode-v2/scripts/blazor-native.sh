#!/bin/sh
# Blazorise replaced by native Razor (the skill blazorise), without any other package: what Qwen should not work out
# by hand, done the same way every time.
#   inventory [<folder>]   read only: each .razor file that uses Blazorise, its tags (with their count) and their family
#                          (simple, form, dialog, grid), in the order the pages are best replaced (the leaves first:
#                          layout and simple pages, then forms, then dialogs and messages, then grids); a tag that is
#                          neither the application's, nor of ASP.NET Core, nor known of Blazorise is named to check; the
#                          services of Blazorise the code injects, its registrations (AddBlazorise…), its links
#                          (_content/Blazorise…), its packages and its version, the configuration keys of its license
#                          (their names, never their values); then the native equivalent of each tag used.
#   scaffold <project>     the native components of the application, in <project>/Components/Native (or Shared/Native
#                          when the project has a Shared folder and no Components one), in the namespace of the project:
#                          NativeGrid and its columns NativeColumn, NativeTemplateColumn (a table: a sort by a click on
#                          a title, the pages and a French pager, the text of an empty list, a click on a row and the
#                          selected row, the data of a server by ItemsProvider), NativeModal, NativeDialogService and
#                          NativeDialogHost (the questions and messages of IMessageService), NativeToastService and
#                          NativeToastHost (the messages of INotificationService), and the Bootstrap classes of a field
#                          (NativeFieldCssClassProvider); plus their @using in _Imports.razor. All named Native…, so that
#                          none meets a name of Blazorise while both are there. Plain Razor and C# for .NET 8 and later,
#                          the Bootstrap classes the application loads, no package. A file that exists is never written
#                          again: the application owns these components once they are there.
#   check [<folder>]       read only: what is left of Blazorise, each with its file and line: projects (PackageReference,
#                          PackageVersion, Using), usings, registrations, links, tags, services, its configuration and
#                          license keys (names only);
#                          "BLAZORISE: GONE" when nothing is left (the Markdown documentation excepted), exit 1 otherwise.
# Output: "INVENTORY:", "PAGE:", "UNKNOWN TAG:", "SERVICE:", "REGISTRATION:", "LINK:", "PACKAGE:", "LICENSE KEY:",
# "EQUIVALENT:", "PLAN:" (inventory); "SCAFFOLD:", "WRITTEN:", "KEPT:", "IMPORTS:", "NEXT:" (scaffold); "LEFT:" lines and
# "BLAZORISE: GONE" or "BLAZORISE: <n> place(s) left" (check); "STOP:" when an argument is wrong.
# Usage: blazor-native.sh inventory [<folder>] | scaffold <project folder or .csproj> | check [<folder>]

LC_ALL=C
export LC_ALL
action=$1
[ $# -gt 0 ] && shift
root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "STOP: not a git repository"; exit 1; }
cd "$root" || exit 1
tmp=$(mktemp -d "${TMPDIR:-/tmp}/blazor-native.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT

# The components of ASP.NET Core and of Razor (never Blazorise), and the families of the tags of Blazorise, by their names
BUILTIN='EditForm|InputText|InputTextArea|InputNumber|InputDate|InputSelect|InputCheckbox|InputRadio|InputRadioGroup|InputFile|DataAnnotationsValidator|ObjectGraphDataAnnotationsValidator|ValidationMessage|ValidationSummary|NavLink|PageTitle|HeadOutlet|HeadContent|Router|RouteView|Found|NotFound|Navigating|AuthorizeView|Authorized|NotAuthorized|Authorizing|AuthorizeRouteView|CascadingValue|CascadingAuthenticationState|DynamicComponent|ErrorBoundary|ErrorContent|Virtualize|ItemContent|Placeholder|EmptyContent|QuickGrid|PropertyColumn|TemplateColumn|Paginator|LayoutView|ChildContent|Routes|App|FocusOnNavigate|SectionContent|SectionOutlet|AntiforgeryToken|ImportMap|ReconnectModal|NativeGrid|NativeColumn|NativeTemplateColumn|NativeGridDefer|NativeModal|NativeDialogHost|NativeToastHost|Footer'
OTHER_LIBS='^(Mud|Radzen|Telerik|Sf[A-Z]|Fluent|Ant[A-Z]|Bit[A-Z]|Havit)'
FAMILY_GRID='^(DataGrid|Table|Pagination|Pager)'
FAMILY_DIALOG='^(Modal|CloseButton|Snackbar|Toast|Toaster|Alert|Message|Notification|PageProgress|Tooltip|Dropdown|Tab|Tabs|TabPanel|TabsContent|Offcanvas|Popover|Collapse|Accordion)'
FAMILY_FORM='^(TextInput|TextEdit|NumericInput|NumericEdit|NumericPicker|DateInput|DateEdit|DatePicker|TimeInput|TimeEdit|TimePicker|MemoInput|MemoEdit|Select|SelectItem|SelectGroup|Check|Switch|RadioGroup|Radio|FileInput|FileEdit|FilePicker|Validations|Validation|ValidationError|ValidationSuccess|ValidationSummary|Feedback|Field|Fields|FieldLabel|FieldHelp|FieldBody|Addons|Addon|AddonLabel|Autocomplete|ColorInput|ColorEdit|ColorPicker|Slider|Rating|InputMask|Form)'
# The tags of Blazorise that are not of these families (layout, text, buttons, icons…): known, so that a tag of another
# library is never taken for one
KNOWN_SIMPLE='^(Button|Buttons|Icon|Badge|Card|CardBody|CardHeader|CardFooter|CardTitle|CardSubtitle|CardText|CardImage|CardDeck|CardGroup|CardLink|Row|Column|Container|Div|Span|Heading|Paragraph|Text|Small|Strong|Code|Blockquote|Image|Figure|Divider|Bar|BarBrand|BarToggler|BarMenu|BarStart|BarEnd|BarItem|BarLink|BarDropdown|BarDropdownMenu|BarDropdownItem|BarDropdownToggle|Progress|ProgressBar|Spinner|SpinKit|Link|Layout|LayoutHeader|LayoutSider|LayoutSiderContent|LayoutContent|LayoutFooter|Breadcrumb|BreadcrumbItem|BreadcrumbLink|ListGroup|ListGroupItem|Jumbotron|JumbotronTitle|JumbotronSubtitle|Label|ThemeProvider|Steps|Step|StepPanel|StepsContent|Carousel|CarouselSlide|Chart|LineChart|BarChart|PieChart|DoughnutChart|RichTextEdit|Markdown|Highlighter|UnorderedList|UnorderedListItem|OrderedList|OrderedListItem|DescriptionList|DescriptionListTerm|DescriptionListDefinition|Address|Anchor|Video|Repeater|LoadingIndicator|Skeleton|SkeletonItem|Callout|Kbd|Mark|Inline|Card[A-Z][A-Za-z]*|Layout[A-Z][A-Za-z]*|Bar[A-Z][A-Za-z]*)$'

# the files of the repository, those not committed yet included (the work of the step under way)
razor_files() {
  git ls-files --cached --others --exclude-standard ${1:+"$1"} | grep -E '\.razor$' | sort -u
}
# The tags of a .razor file: "<Tag> <line>", one per occurrence; never in its Razor comments (@* *@), its @code and
# @functions blocks, nor a C# generic (List<TItem>: a letter before the <)
tags_of() {
  awk '{
    line = $0; out = ""
    while (line != "") {
      if (incomment) { i = index(line, "*@"); if (!i) { line = ""; break }; line = substr(line, i + 2); incomment = 0; continue }
      i = index(line, "@*"); if (!i) { out = out line; break }
      out = out substr(line, 1, i - 1); line = substr(line, i + 2); incomment = 1
    }
    line = out
    if (!incode && line ~ /^[[:space:]]*@(code|functions)([^A-Za-z0-9_]|$)/) { incode = 1; depth = 0 }
    if (incode) { o = gsub(/\{/, "{", line); c = gsub(/\}/, "}", line); depth += o - c; if (depth <= 0 && o + c > 0) incode = 0; next }
    s = line
    while (match(s, /(^|[^A-Za-z0-9_.])<[A-Z][A-Za-z0-9]*/)) { t = substr(s, RSTART, RLENGTH); sub(/^[^<]*</, "", t); print t " " NR; s = substr(s, RSTART + RLENGTH) }
  }' "$1"
}
# A license key written in the code: its value never printed
mask() {
  sed -E 's/((ProductToken|LicenseKey)[[:space:]]*=[[:space:]]*)"[^"]*"/\1"…"/g'
}
# The components of the application: one per .razor file (its name)
git ls-files --cached --others --exclude-standard '*.razor' | sed -E 's#.*/##; s#\.razor$##' | sort -u > "$tmp/app"
# Whether a .razor file sees the namespaces of Blazorise: its own @using, or an _Imports.razor above it
imports_blazorise() {
  grep -q -E '^@using +Blazorise' "$1" 2>/dev/null && return 0
  d=$(dirname "$1")
  while :; do
    [ -f "$d/_Imports.razor" ] && grep -q -E '^@using +Blazorise' "$d/_Imports.razor" && return 0
    [ "$d" = . ] || [ "$d" = / ] && return 1
    d=$(dirname "$d")
  done
}
# blazorise_tags <file>: "<Tag> <line>" for each tag of Blazorise of the file (or a tag to check: "?<Tag> <line>")
blazorise_tags() {
  imports_blazorise "$1" || return 0
  tags_of "$1" | while read -r tag line; do
    printf '%s\n' "$tag" | grep -q -x -E "$BUILTIN" && continue
    grep -q -x -F "$tag" "$tmp/app" && continue
    printf '%s\n' "$tag" | grep -q -E "$OTHER_LIBS" && continue
    if printf '%s\n' "$tag" | grep -q -E "$FAMILY_GRID|$FAMILY_DIALOG|$FAMILY_FORM|$KNOWN_SIMPLE"; then echo "$tag $line"; else echo "?$tag $line"; fi
  done
}
family() {
  if printf '%s\n' "$1" | grep -q -E "$FAMILY_GRID"; then echo "4 grid"
  elif printf '%s\n' "$1" | grep -q -E "$FAMILY_DIALOG"; then echo "3 dialog"
  elif printf '%s\n' "$1" | grep -q -E "$FAMILY_FORM"; then echo "2 form"
  else echo "1 simple"; fi
}
# The native equivalent of a tag, in a few words (the skill blazorise gives the details)
equivalent() {
  case "$1" in
    DataGrid) echo "NativeGrid (Items=, ShowPager, PageSize, EmptyText, RowClicked, @bind-SelectedItem; ReadData -> ItemsProvider)" ;;
    DataGridColumn) echo "NativeColumn (Field=\"@(o => o.X)\" Title= Format=; DisplayFormat {0:N2} works as is)" ;;
    DataGridCommandColumn|DataGridSelectColumn|DataGridMultiSelectColumn|DataGridCheckColumn) echo "NativeTemplateColumn with its buttons or a checkbox (edit: an EditForm in NativeModal)" ;;
    DataGrid*) echo "NativeGrid and its columns (see the skill: no direct equivalent, a template or a C# computation)" ;;
    Table|TableHeader|TableBody|TableRow|TableHeaderCell|TableRowCell|TableRowHeader|TableFooter) echo "<table class=\"table\">, <thead>, <tbody>, <tr>, <th>, <td>" ;;
    Pagination*|Pager*) echo "the pager of NativeGrid, or buttons over a page index" ;;
    TextInput|TextEdit) echo "InputText (a value on each key: <input @bind=\"x\" @bind:event=\"oninput\">)" ;;
    NumericInput|NumericEdit|NumericPicker) echo "InputNumber" ;;
    DateInput|DateEdit|DatePicker) echo "InputDate (the date picker of the browser)" ;;
    TimeInput|TimeEdit|TimePicker) echo "InputDate Type=\"InputDateType.Time\"" ;;
    MemoInput|MemoEdit) echo "InputTextArea" ;;
    Select|SelectItem|SelectGroup) echo "InputSelect, <option>, <optgroup>" ;;
    Check) echo "InputCheckbox in <div class=\"form-check\">" ;;
    Switch) echo "InputCheckbox in <div class=\"form-check form-switch\"> role=\"switch\"" ;;
    RadioGroup|Radio) echo "InputRadioGroup, InputRadio" ;;
    FileInput|FileEdit|FilePicker) echo "InputFile" ;;
    Validations|Validation|ValidationError|ValidationSuccess|Feedback) echo "EditForm + DataAnnotationsValidator + ValidationMessage, NativeFieldCssClassProvider" ;;
    Field|Fields|FieldBody) echo "<div class=\"mb-3\">" ;;
    FieldLabel) echo "<label class=\"form-label\">" ;;
    FieldHelp) echo "<div class=\"form-text\">" ;;
    Addons|Addon|AddonLabel) echo "<div class=\"input-group\">, <span class=\"input-group-text\">" ;;
    Autocomplete) echo "<input list=\"…\"> and a <datalist>" ;;
    Modal|ModalContent|ModalHeader|ModalTitle|ModalBody|ModalFooter|CloseButton) echo "NativeModal (@bind-Visible, Title; with buttons: <ChildContent>…</ChildContent><Footer>…</Footer>; or @ref and Show()/Hide())" ;;
    ModalProvider) echo "nothing: a NativeModal in the page, the component inside it" ;;
    MessageProvider|Message*) echo "NativeDialogService (ConfirmAsync, AlertAsync) + <NativeDialogHost /> in the layout" ;;
    NotificationProvider|Notification*|Snackbar*|Toast*) echo "NativeToastService (Success, Info, Warning, Error) + <NativeToastHost /> in the layout" ;;
    Alert) echo "<div class=\"alert alert-…\" role=\"alert\">" ;;
    PageProgress*) echo "<div class=\"progress\"> shown with @if" ;;
    Tooltip) echo "the title attribute" ;;
    Dropdown*) echo "<div class=\"dropdown\"> with <ul class=\"dropdown-menu\"> shown by a bool (class show)" ;;
    Tab|Tabs|TabPanel|TabsContent) echo "<ul class=\"nav nav-tabs\"> and the active tab in a field" ;;
    Collapse*|Accordion*) echo "<details><summary>, or a bool and the class show" ;;
    Button) echo "<button type=\"button\" class=\"btn btn-…\">" ;;
    Icon) echo "<i class=\"…\" aria-hidden=\"true\"></i> with the icon CSS the application loads (its own link, not _content/Blazorise…)" ;;
    Badge) echo "<span class=\"badge text-bg-…\">" ;;
    Card*) echo "<div class=\"card\">, card-body, card-header, card-title…" ;;
    Row) echo "<div class=\"row\">" ;;
    Column) echo "<div class=\"col-…\">" ;;
    Container) echo "<div class=\"container\">" ;;
    Div|Span|Paragraph|Text|Small|Strong|Code|Blockquote|Label|Address|Mark|Kbd) echo "the HTML element of the same name (div, span, p, small, strong, code, label…)" ;;
    Heading) echo "<h1> to <h6>" ;;
    Image) echo "<img class=\"img-fluid\">" ;;
    Divider) echo "<hr>" ;;
    Bar*) echo "<nav class=\"navbar\"> and NavLink" ;;
    Progress*) echo "<div class=\"progress\"><div class=\"progress-bar\">" ;;
    Spinner|SpinKit|LoadingIndicator) echo "<div class=\"spinner-border\" role=\"status\">" ;;
    Link|Anchor) echo "<a href> or NavLink" ;;
    Layout*) echo "the layout of the application (MainLayout.razor), its own markup" ;;
    Breadcrumb*) echo "<nav aria-label=\"breadcrumb\"><ol class=\"breadcrumb\">" ;;
    ListGroup*) echo "<ul class=\"list-group\">, <li class=\"list-group-item\">" ;;
    UnorderedList*|OrderedList*|DescriptionList*) echo "<ul>, <ol>, <dl>" ;;
    ThemeProvider) echo "nothing (the Bootstrap CSS of the application)" ;;
    Chart|*Chart|RichTextEdit|Markdown|Highlighter|Carousel*|Steps|Step|StepPanel|StepsContent) echo "a step of its own (a small JS module or a component of the application): the skill blazorise" ;;
    *) echo "see the skill blazorise" ;;
  esac
}

case "$action" in
  inventory)
    folder=$1
    [ -z "$folder" ] || [ -e "$folder" ] || { echo "STOP: no folder $folder"; exit 1; }
    version=$(git grep --untracked -h -o -i -E 'Include="Blazorise[^"]*"[^>]*Version="[0-9][^"]*"' -- '*.csproj' 'Directory.Packages.props' 2>/dev/null | sed -E 's/.*Version="([^"]*)".*/\1/' | sort -u | head -n 1)
    : > "$tmp/pages"
    : > "$tmp/used"
    razor_files "$folder" | while IFS= read -r f; do
      blazorise_tags "$f" > "$tmp/tags"
      [ -s "$tmp/tags" ] || continue
      grep -v '^?' "$tmp/tags" | cut -d' ' -f1 >> "$tmp/used"
      rank=1
      for tag in $(grep -v '^?' "$tmp/tags" | cut -d' ' -f1 | sort -u); do
        r=$(family "$tag" | cut -d' ' -f1)
        [ "$r" -gt "$rank" ] && rank=$r
      done
      count=$(grep -c . "$tmp/tags")
      list=$(grep -v '^?' "$tmp/tags" | cut -d' ' -f1 | sort | uniq -c | sort -rn | awk '{ printf "%s%s×%s", (NR > 1 ? ", " : ""), $2, $1 }')
      case "$rank" in 1) fam=simple ;; 2) fam=form ;; 3) fam=dialog ;; *) fam=grid ;; esac
      printf '%s\t%s\t%s\t%s\t%s\n' "$rank" "$count" "$f" "$fam" "$list" >> "$tmp/pages"
      grep '^?' "$tmp/tags" | sed 's/^?//' | while read -r tag line; do printf 'UNKNOWN TAG: <%s> in %s:%s (neither of the application, nor of ASP.NET Core, nor known of Blazorise: check it)\n' "$tag" "$f" "$line"; done >> "$tmp/unknown"
    done
    n=$(grep -c . "$tmp/pages")
    total=$(awk -F '\t' '{ s += $2 } END { print s + 0 }' "$tmp/pages")
    echo "INVENTORY: $n .razor file(s) use Blazorise ($total tags in all)${version:+, Blazorise $version}"
    # the leaves first: the family, then the fewer tags
    sort -t "$(printf '\t')" -k1,1n -k2,2n -k3,3 "$tmp/pages" | awk -F '\t' '{ printf "PAGE: %s — %s: %s — step %d\n", $3, $4, ($5 == "" ? "only tags to check" : $5), NR }'
    [ -f "$tmp/unknown" ] && cat "$tmp/unknown"
    git grep --untracked -n -E '(INotificationService|IMessageService|IModalService|IToastService|IPageProgressService|ITextLocalizerService|ITextLocalizer<)' -- '*.cs' '*.razor' 2>/dev/null |
      sed -E 's/^([^:]*:[0-9]+):.*(INotificationService|IMessageService|IModalService|IToastService|IPageProgressService|ITextLocalizerService|ITextLocalizer<).*/SERVICE: \2 in \1/; s/ITextLocalizer<$/ITextLocalizer<…>/' |
      sed -E 's/^(SERVICE: IMessageService .*)/\1 -> NativeDialogService (ConfirmAsync; Info, Success, Warning, Error: AlertAsync)/
              s/^(SERVICE: (INotificationService|IToastService) .*)/\1 -> NativeToastService (Success, Info, Warning, Error)/
              s/^(SERVICE: IModalService .*)/\1 -> a NativeModal in the page, the component inside it/
              s/^(SERVICE: IPageProgressService .*)/\1 -> a <div class="progress"> shown with @if/
              s/^(SERVICE: ITextLocalizer.*)/\1 -> nothing: the native components speak French/'
    git grep --untracked -n -E 'AddBlazorise|AddBootstrap5?Providers|AddBulmaProviders|AddMaterialProviders|AddAntDesignProviders|AddTailwindProviders|AddFluent2Providers|AddFontAwesomeIcons|AddMaterialIcons|AddBootstrapIcons|AddFluentUIIcons|AddBlazorise[A-Za-z]*' -- '*.cs' 2>/dev/null |
      sed -E 's/^([^:]*:[0-9]+):[[:space:]]*(.*)$/REGISTRATION: \1 \2/' | mask | cut -c1-200
    git grep --untracked -n -E '_content/Blazorise' -- '*.razor' '*.cshtml' '*.html' 2>/dev/null | sed -E 's/^([^:]*:[0-9]+):.*(_content\/Blazorise[^"'"'"' >]*).*/LINK: \1 \2/'
    git grep --untracked -h -o -E 'Include="Blazorise[^"]*"[^>]*' -- '*.csproj' 'Directory.Packages.props' 2>/dev/null | sed -E 's/Include="([^"]*)".*Version="([^"]*)".*/\1 \2/; s/Include="([^"]*)".*/\1/' | sort -u |
      awk '{ printf "%s%s", (NR > 1 ? ", " : "PACKAGE: "), $0 } END { if (NR) print "" }'
    # the license: the names of its keys, never a value
    git grep --untracked -n -o -E '"(ProductToken|LicenseKey)"|(ProductToken|LicenseKey)[[:space:]]*=' -- '*.json' '*.cs' 2>/dev/null | grep -i -v test |
      sed -E 's/^([^:]*:[0-9]+):.*(ProductToken|LicenseKey).*/LICENSE KEY: \1 \2 (its value is never printed: the developer removes it from the configuration and the secret stores)/' | sort -u
    if [ -s "$tmp/used" ]; then
      sort -u "$tmp/used" | while IFS= read -r tag; do echo "EQUIVALENT: <$tag> -> $(equivalent "$tag")"; done
    fi
    if [ "$n" -gt 0 ]; then
      grid=$(grep -c -E '^4	' "$tmp/pages")
      dialogs=$(grep -c -E '^3	' "$tmp/pages")
      echo "PLAN: a first step that writes the native components (blazor-native.sh scaffold <the web project>), then one page per step in the order of the PAGE lines, each « (filet d'abord) » and « (s'appuyer sur le skill blazorise) »$([ "$grid" -gt 0 ] && echo " ($grid with a grid: NativeGrid)")$([ "$dialogs" -gt 0 ] && echo " ($dialogs with dialogs or messages: NativeModal, NativeDialogHost, NativeToastHost)"); the last step removes the packages, the registrations, the usings, the links and the license keys (blazor-native.sh check says BLAZORISE: GONE)"
    else
      echo "PLAN: no .razor file uses Blazorise; blazor-native.sh check says what may be left (packages, registrations, links)"
    fi
    exit 0 ;;

  check)
    folder=$1
    [ -z "$folder" ] || [ -e "$folder" ] || { echo "STOP: no folder $folder"; exit 1; }
    : > "$tmp/left"
    git grep --untracked -n -i -E 'Include="Blazorise' -- ${folder:+"$folder"} '*.csproj' 'Directory.Packages.props' '*.props' '*.targets' 2>/dev/null | sed 's/^/LEFT: project: /' >> "$tmp/left"
    git grep --untracked -n -E '^[[:space:]]*@using +Blazorise|^[[:space:]]*using +Blazorise|^[[:space:]]*global using +Blazorise' -- ${folder:+"$folder"} '*.razor' '*.cs' 2>/dev/null | sed 's/^/LEFT: using: /' >> "$tmp/left"
    git grep --untracked -n -E 'AddBlazorise|AddBootstrap5?Providers|AddFontAwesomeIcons|AddMaterialIcons|AddBootstrapIcons|UseBlazorise' -- ${folder:+"$folder"} '*.cs' 2>/dev/null | mask | sed 's/^/LEFT: registration: /' >> "$tmp/left"
    git grep --untracked -n -E '_content/Blazorise' -- ${folder:+"$folder"} '*.razor' '*.cshtml' '*.html' 2>/dev/null | sed 's/^/LEFT: link: /' >> "$tmp/left"
    git grep --untracked -n -E '(INotificationService|IMessageService|IModalService|IToastService|IPageProgressService|ITextLocalizerService)' -- ${folder:+"$folder"} '*.cs' '*.razor' 2>/dev/null | sed 's/^/LEFT: service: /' >> "$tmp/left"
    git grep --untracked -n -o -E '"(ProductToken)"|ProductToken[[:space:]]*=' -- ${folder:+"$folder"} '*.json' '*.cs' 2>/dev/null | sed -E 's/^([^:]*:[0-9]+):.*/LEFT: license key: \1 ProductToken (its value is never printed)/' >> "$tmp/left"
    git grep --untracked -n -o -E '"Blazorise"[[:space:]]*:' -- ${folder:+"$folder"} '*.json' 2>/dev/null | sed -E 's/^([^:]*:[0-9]+):.*/LEFT: configuration: \1 the section "Blazorise"/' >> "$tmp/left"
    razor_files "$folder" | while IFS= read -r f; do
      # without the using, a tag of Blazorise no longer compiles: its tags are those the known lists name
      tags_of "$f" | while read -r tag line; do
        printf '%s\n' "$tag" | grep -q -x -E "$BUILTIN" && continue
        grep -q -x -F "$tag" "$tmp/app" && continue
        printf '%s\n' "$tag" | grep -q -E "$OTHER_LIBS" && continue
        printf '%s\n' "$tag" | grep -q -E "$FAMILY_GRID|$FAMILY_DIALOG|$FAMILY_FORM|$KNOWN_SIMPLE" &&
          echo "LEFT: tag: $f:$line <$tag>"
      done
    done >> "$tmp/left"
    # the dll of the packages left in the outputs are not the code: never counted
    n=$(grep -c . "$tmp/left")
    if [ "$n" -eq 0 ]; then
      echo "BLAZORISE: GONE (no package, using, registration, link, service, tag or license key of Blazorise in the code and the projects; the Markdown documentation is not looked at)"
      exit 0
    fi
    cat "$tmp/left"
    echo "BLAZORISE: $n place(s) left"
    exit 1 ;;

  scaffold) ;;
  *)
    echo "STOP: blazor-native.sh inventory [<folder>] | scaffold <project folder or .csproj> | check [<folder>]"
    exit 1 ;;
esac

# ---------- scaffold ----------
target=$1
[ -n "$target" ] || { echo "STOP: blazor-native.sh scaffold <the folder of the web project, or its .csproj>"; exit 1; }
case "$target" in
  *.csproj) csproj=$target ;;
  *) csproj=$(find "$target" -maxdepth 1 -name '*.csproj' 2>/dev/null | head -n 1) ;;
esac
[ -n "$csproj" ] && [ -f "$csproj" ] || { echo "STOP: no .csproj in $target"; exit 1; }
project=$(dirname "$csproj")
grep -q -E 'Sdk="Microsoft\.NET\.Sdk\.(Web|Razor|BlazorWebAssembly)"' "$csproj" || { echo "STOP: $csproj is not a Blazor or Razor project (Sdk Web, Razor or BlazorWebAssembly)"; exit 1; }
tfm=$(sed -n 's#.*<TargetFrameworks\{0,1\}>\([^<]*\)</TargetFrameworks\{0,1\}>.*#\1#p' "$csproj" | head -n 1)
case "$tfm" in
  *net[89].0*|*net1[0-9].0*) ;;
  *) echo "STOP: the native components are written for .NET 8 and later; $csproj targets ${tfm:-an unknown framework}"; exit 1 ;;
esac
# the namespace of the project: its RootNamespace, otherwise the name of the project (what Razor gives its components)
ns=$(sed -n 's#.*<RootNamespace>\([^<]*\)</RootNamespace>.*#\1#p' "$csproj" | head -n 1)
[ -n "$ns" ] || ns=$(basename "$csproj" .csproj | sed 's/[^A-Za-z0-9_.]/_/g')
if [ -d "$project/Components" ] || [ ! -d "$project/Shared" ]; then sub=Components/Native; else sub=Shared/Native; fi
dir="$project/$sub"
nsn="$ns.$(printf '%s' "$sub" | tr '/' '.')"
mkdir -p "$dir"
echo "SCAFFOLD: $dir (namespace $nsn, $tfm)"

# write <file name>: the text of its standard input, with the namespace of the application, unless the file exists
write() {
  if [ -f "$dir/$1" ]; then
    echo "KEPT: $dir/$1 (exists: the application owns it)"
    cat > /dev/null
    return 0
  fi
  sed "s/__NS__/$nsn/g" > "$dir/$1"
  echo "WRITTEN: $dir/$1"
}

write NativeGridTypes.cs <<'EOF'
using System.Collections.Generic;
using System.Threading;
using Microsoft.AspNetCore.Components;
using Microsoft.AspNetCore.Components.Rendering;

namespace __NS__;

// What NativeGrid asks of the data of a server (its ItemsProvider), what it gets back, and the
// small component that lets it draw its table once its columns are known. Written by blazor-native.sh scaffold; the
// application owns it.

/// <summary>A page of data asked by a NativeGrid: from <see cref="StartIndex"/>, <see cref="Count"/> rows, sorted by
/// <see cref="SortBy"/> (the member of its column: "Date", "Customer.Name"; the title of a template column), from the
/// largest when <see cref="Descending"/>.</summary>
public sealed record NativeGridRequest(int StartIndex, int Count, string? SortBy, bool Descending, CancellationToken CancellationToken);

/// <summary>The rows of a page, and how many rows there are in all.</summary>
public sealed record NativeGridResult<TItem>(IReadOnlyList<TItem> Items, int TotalItemCount);

/// <summary>Renders its content after the components before it: NativeGrid draws its table once its columns rendered.</summary>
public sealed class NativeGridDefer : ComponentBase
{
    [Parameter]
    public RenderFragment? ChildContent { get; set; }

    protected override void BuildRenderTree(RenderTreeBuilder builder) => builder.AddContent(0, ChildContent);
}
EOF

write NativeColumnBase.cs <<'EOF'
using System;
using System.Collections.Generic;
using Microsoft.AspNetCore.Components;
using Microsoft.AspNetCore.Components.Rendering;

namespace __NS__;

// A column of a NativeGrid: its title, whether a click sorts by it, and how it renders a cell. NativeColumn (a value) and
// NativeTemplateColumn (a template) are its two kinds. A column draws nothing itself: each time its grid renders, it
// takes its place among the columns, so that a column shown under a condition, or a title that changes, is right at
// once. Written by blazor-native.sh scaffold; the application owns it.
public abstract class NativeColumnBase<TItem> : ComponentBase
{
    [CascadingParameter]
    internal NativeGrid<TItem>? Grid { get; set; }

    /// <summary>The title of the column, in its header.</summary>
    [Parameter]
    public string? Title { get; set; }

    /// <summary>A click on the title sorts the rows by this column, a second one from the largest (true by
    /// default).</summary>
    [Parameter]
    public bool Sortable { get; set; } = true;

    /// <summary>The rows are sorted by this column first.</summary>
    [Parameter]
    public bool IsDefaultSort { get; set; }

    /// <summary>The first sort goes from the largest.</summary>
    [Parameter]
    public bool Descending { get; set; }

    [Parameter]
    public string? HeaderClass { get; set; }

    [Parameter]
    public string? CellClass { get; set; }

    internal abstract bool CanSort { get; }

    internal abstract string? SortName { get; }

    internal abstract IEnumerable<TItem> Sort(IEnumerable<TItem> items, bool descending);

    internal abstract RenderFragment Cell(TItem item);

    protected override void OnInitialized()
    {
        if (Grid is null)
        {
            throw new InvalidOperationException($"{GetType().Name} goes inside a NativeGrid.");
        }
    }

    protected override void BuildRenderTree(RenderTreeBuilder builder) => Grid?.CollectColumn(this);
}
EOF

write NativeColumn.cs <<'EOF'
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Linq.Expressions;
using Microsoft.AspNetCore.Components;

namespace __NS__;

// NativeColumn: a column of a NativeGrid that shows a value, in a format.
// Written by blazor-native.sh scaffold; the application owns it.
public sealed class NativeColumn<TItem, TValue> : NativeColumnBase<TItem>
{
    private static readonly bool Comparable = typeof(IComparable).IsAssignableFrom(Nullable.GetUnderlyingType(typeof(TValue)) ?? typeof(TValue));

    private Func<TItem, TValue>? value;
    private string? path;

    /// <summary>The value of the column: Field="@(o => o.Date)".</summary>
    [Parameter, EditorRequired]
    public Expression<Func<TItem, TValue>> Field { get; set; } = default!;

    /// <summary>Its format, in the culture of the user: "dd/MM/yyyy", "N2", or a composite one, "{0:N2}".</summary>
    [Parameter]
    public string? Format { get; set; }

    internal override bool CanSort => Sortable && Comparable && value is not null;

    internal override string? SortName => path ?? Title;

    protected override void OnParametersSet()
    {
        // the page gives a new expression at each of its renders: compiled again only when it reads another member
        var read = PathOf(Field);
        if (value is null || read is null || read != path)
        {
            value = Field.Compile();
        }

        path = read;
    }

    internal override IEnumerable<TItem> Sort(IEnumerable<TItem> items, bool descending) =>
        value is null ? items : descending ? items.OrderByDescending(value) : items.OrderBy(value);

    internal override RenderFragment Cell(TItem item) => builder => builder.AddContent(0, Text(item));

    private string Text(TItem item)
    {
        object? cell = value is null ? null : (object?)value(item);
        if (cell is null)
        {
            return string.Empty;
        }

        if (string.IsNullOrEmpty(Format))
        {
            return Convert.ToString(cell, CultureInfo.CurrentCulture) ?? string.Empty;
        }

        if (Format.Contains("{0", StringComparison.Ordinal))
        {
            return string.Format(CultureInfo.CurrentCulture, Format, cell);
        }

        return cell is IFormattable formattable ? formattable.ToString(Format, CultureInfo.CurrentCulture) : cell.ToString() ?? string.Empty;
    }

    // "Customer.Name" for o => o.Customer.Name; null when the expression is not members of the row only
    private static string? PathOf(Expression<Func<TItem, TValue>>? field)
    {
        if (field is null)
        {
            return null;
        }

        Expression? body = field.Body is UnaryExpression { NodeType: ExpressionType.Convert } convert ? convert.Operand : field.Body;
        var names = new List<string>();
        while (body is MemberExpression member)
        {
            names.Insert(0, member.Member.Name);
            body = member.Expression;
        }

        return names.Count > 0 && body == field.Parameters[0] ? string.Join(".", names) : null;
    }
}
EOF

write NativeTemplateColumn.cs <<'EOF'
using System;
using System.Collections.Generic;
using System.Linq;
using Microsoft.AspNetCore.Components;

namespace __NS__;

// NativeTemplateColumn: a column of a NativeGrid that renders a template for each row, its context (buttons, a link, a
// checkbox, any markup). A button in a clickable row:
// @onclick:stopPropagation="true", so that its click is not a click on the row too.
// Written by blazor-native.sh scaffold; the application owns it.
public sealed class NativeTemplateColumn<TItem> : NativeColumnBase<TItem>
{
    /// <summary>The content of a cell; context is its row.</summary>
    [Parameter, EditorRequired]
    public RenderFragment<TItem> ChildContent { get; set; } = default!;

    /// <summary>The value its sort uses, when a click on its title sorts the rows: SortBy="@(o => o.Total)".</summary>
    [Parameter]
    public Func<TItem, IComparable?>? SortBy { get; set; }

    internal override bool CanSort => Sortable && SortBy is not null;

    internal override string? SortName => Title;

    internal override IEnumerable<TItem> Sort(IEnumerable<TItem> items, bool descending) =>
        SortBy is null ? items : descending ? items.OrderByDescending(SortBy) : items.OrderBy(SortBy);

    internal override RenderFragment Cell(TItem item) => ChildContent(item);
}
EOF

write NativeGrid.razor <<'EOF'
@* NativeGrid: the grid of the application in native Razor, without any package: a Bootstrap table, its
   columns (NativeColumn, NativeTemplateColumn), a sort by a click on a title, the pages and their French pager (the
   words Première, Précédente, Suivante, Dernière), the text of an empty list, a click on a row and the
   selected row, the data in memory (Items) or of a server (ItemsProvider). Written by blazor-native.sh scaffold; the
   application owns it. *@
@namespace __NS__
@using System.Threading
@using Microsoft.AspNetCore.Components.Web
@typeparam TItem
@attribute [CascadingTypeParameter(nameof(TItem))]
@implements IDisposable

<CascadingValue TValue="NativeGrid<TItem>" Value="this" IsFixed="true">
    @{ StartCollecting(); }
    @ChildContent
    <NativeGridDefer>
        @{ FinishCollecting(); }
        @if (columns.Count > 0)
        {
            var rows = CurrentRows();
            var clickable = RowClicked.HasDelegate || SelectedItemChanged.HasDelegate;
            <table class="@TableClass">
                <thead>
                    <tr>
                        @foreach (var column in columns)
                        {
                            <th scope="col" class="@column.HeaderClass" aria-sort="@AriaSort(column)">
                                @if (column.CanSort)
                                {
                                    <button type="button" class="btn btn-link p-0 fw-semibold text-reset text-decoration-none" @onclick="() => SortByAsync(column)">@column.Title</button>
                                }
                                else
                                {
                                    @column.Title
                                }
                            </th>
                        }
                    </tr>
                </thead>
                <tbody>
                    @if (rows.Count == 0)
                    {
                        <tr>
                            <td colspan="@columns.Count" class="text-center text-body-secondary">@(Loading ? LoadingText : EmptyText)</td>
                        </tr>
                    }
                    else
                    {
                        foreach (var item in rows)
                        {
                            if (clickable)
                            {
                                <tr role="button" tabindex="0" class="@RowCss(item)" @onclick="() => ClickAsync(item)" @onkeydown="e => OnRowKeyAsync(e, item)">
                                    @foreach (var column in columns)
                                    {
                                        <td class="@column.CellClass">@column.Cell(item)</td>
                                    }
                                </tr>
                            }
                            else
                            {
                                <tr class="@RowCss(item)">
                                    @foreach (var column in columns)
                                    {
                                        <td class="@column.CellClass">@column.Cell(item)</td>
                                    }
                                </tr>
                            }
                        }
                    }
                </tbody>
            </table>
            if (Paged && total > 0)
            {
                <nav class="d-flex flex-wrap align-items-center gap-2" aria-label="Pagination">
                    <button type="button" class="btn btn-sm btn-outline-secondary" disabled="@(pageIndex == 0)" @onclick="() => GoToAsync(0)">Première</button>
                    <button type="button" class="btn btn-sm btn-outline-secondary" disabled="@(pageIndex == 0)" @onclick="() => GoToAsync(pageIndex - 1)">Précédente</button>
                    <span>Page @(pageIndex + 1) sur @PageCount · @total @(total > 1 ? "éléments" : "élément")</span>
                    <button type="button" class="btn btn-sm btn-outline-secondary" disabled="@(pageIndex >= PageCount - 1)" @onclick="() => GoToAsync(pageIndex + 1)">Suivante</button>
                    <button type="button" class="btn btn-sm btn-outline-secondary" disabled="@(pageIndex >= PageCount - 1)" @onclick="() => GoToAsync(PageCount - 1)">Dernière</button>
                </nav>
            }
        }
    </NativeGridDefer>
</CascadingValue>

@code {
    /// <summary>The rows, in memory.</summary>
    [Parameter]
    public IEnumerable<TItem>? Items { get; set; }

    /// <summary>The rows of a page, from a server, instead of Items.</summary>
    [Parameter]
    public Func<NativeGridRequest, ValueTask<NativeGridResult<TItem>>>? ItemsProvider { get; set; }

    /// <summary>Its columns: NativeColumn and NativeTemplateColumn.</summary>
    [Parameter]
    public RenderFragment? ChildContent { get; set; }

    /// <summary>The rows go in pages, with the pager; all of them otherwise.</summary>
    [Parameter]
    public bool ShowPager { get; set; }

    /// <summary>The rows of a page (10 by default).</summary>
    [Parameter]
    public int PageSize { get; set; } = 10;

    /// <summary>The text of an empty list.</summary>
    [Parameter]
    public string EmptyText { get; set; } = "Aucun élément";

    [Parameter]
    public string LoadingText { get; set; } = "Chargement…";

    /// <summary>A click on a row, or Enter on it.</summary>
    [Parameter]
    public EventCallback<TItem> RowClicked { get; set; }

    /// <summary>The selected row, shown active: @bind-SelectedItem.</summary>
    [Parameter]
    public TItem? SelectedItem { get; set; }

    [Parameter]
    public EventCallback<TItem> SelectedItemChanged { get; set; }

    /// <summary>The CSS class of a row.</summary>
    [Parameter]
    public Func<TItem, string?>? RowClass { get; set; }

    [Parameter]
    public string TableClass { get; set; } = "table table-striped table-hover align-middle";

    private readonly List<NativeColumnBase<TItem>> columns = new();
    private bool collecting;
    private bool defaultSortChosen;
    private NativeColumnBase<TItem>? sortColumn;
    private bool descending;
    private int pageIndex;
    private int total;
    private bool loading;
    private bool rendered;
    private IReadOnlyList<TItem> served = Array.Empty<TItem>();
    private Func<NativeGridRequest, ValueTask<NativeGridResult<TItem>>>? servedBy;
    private CancellationTokenSource? request;

    private bool Paged => ShowPager && PageSize > 0;

    private int PageCount => Paged ? Math.Max(1, (total + PageSize - 1) / PageSize) : 1;

    private bool Loading => loading || (ItemsProvider is not null && servedBy is null);

    /// <summary>The page shown (0 for the first one).</summary>
    public int PageIndex => pageIndex;

    private void StartCollecting()
    {
        columns.Clear();
        collecting = true;
    }

    internal void CollectColumn(NativeColumnBase<TItem> column)
    {
        if (!collecting)
        {
            return;
        }

        columns.Add(column);
        if (!defaultSortChosen && sortColumn is null && column.IsDefaultSort)
        {
            sortColumn = column;
            descending = column.Descending;
        }
    }

    private void FinishCollecting()
    {
        collecting = false;
        defaultSortChosen |= columns.Count > 0;
        if (sortColumn is not null && !columns.Contains(sortColumn))
        {
            sortColumn = null;
        }
    }

    protected override async Task OnParametersSetAsync()
    {
        // a new provider (another filter): its first page; the first one waits for the columns (their default sort)
        if (rendered && ItemsProvider is not null && !Equals(ItemsProvider, servedBy))
        {
            pageIndex = 0;
            await LoadAsync();
        }
    }

    protected override async Task OnAfterRenderAsync(bool firstRender)
    {
        if (!firstRender)
        {
            return;
        }

        rendered = true;
        if (ItemsProvider is not null)
        {
            await LoadAsync();
            StateHasChanged();
        }
    }

    /// <summary>Asks the server again, on the same page (after a change of its data).</summary>
    public async Task RefreshAsync()
    {
        await LoadAsync();
        StateHasChanged();
    }

    private IReadOnlyList<TItem> CurrentRows()
    {
        if (ItemsProvider is not null)
        {
            return served;
        }

        IEnumerable<TItem> all = Items ?? Enumerable.Empty<TItem>();
        if (sortColumn is not null)
        {
            all = sortColumn.Sort(all, descending);
        }

        var list = all.ToList();
        total = list.Count;
        if (!Paged)
        {
            return list;
        }

        pageIndex = Math.Min(pageIndex, PageCount - 1);
        return list.Skip(pageIndex * PageSize).Take(PageSize).ToList();
    }

    private async Task LoadAsync()
    {
        var provider = ItemsProvider;
        if (provider is null)
        {
            return;
        }

        request?.Cancel();
        var mine = request = new CancellationTokenSource();
        servedBy = provider;
        loading = true;
        var asked = new NativeGridRequest(Paged ? pageIndex * PageSize : 0, Paged ? PageSize : int.MaxValue, sortColumn?.SortName, descending, mine.Token);
        try
        {
            var result = await provider(asked);
            if (!mine.IsCancellationRequested)
            {
                served = result.Items;
                total = result.TotalItemCount;
            }
        }
        catch (OperationCanceledException) when (mine.IsCancellationRequested)
        {
            // a newer request replaced this one
        }
        finally
        {
            if (ReferenceEquals(request, mine))
            {
                loading = false;
            }
        }

        // fewer rows than before (some deleted): the last page that has some
        if (ReferenceEquals(request, mine) && served.Count == 0 && total > 0 && pageIndex > PageCount - 1)
        {
            pageIndex = PageCount - 1;
            await LoadAsync();
        }
    }

    private async Task SortByAsync(NativeColumnBase<TItem> column)
    {
        descending = ReferenceEquals(sortColumn, column) ? !descending : column.Descending;
        sortColumn = column;
        pageIndex = 0;
        await LoadAsync();
    }

    private async Task GoToAsync(int index)
    {
        pageIndex = Math.Clamp(index, 0, PageCount - 1);
        await LoadAsync();
    }

    private async Task ClickAsync(TItem item)
    {
        if (SelectedItemChanged.HasDelegate)
        {
            SelectedItem = item;
            await SelectedItemChanged.InvokeAsync(item);
        }

        await RowClicked.InvokeAsync(item);
    }

    private Task OnRowKeyAsync(KeyboardEventArgs e, TItem item) =>
        e.Key is "Enter" or " " ? ClickAsync(item) : Task.CompletedTask;

    private string? RowCss(TItem item)
    {
        var css = RowClass?.Invoke(item);
        if (!SelectedItemChanged.HasDelegate || !EqualityComparer<TItem>.Default.Equals(item, SelectedItem))
        {
            return css;
        }

        return string.IsNullOrEmpty(css) ? "table-active" : css + " table-active";
    }

    private string? AriaSort(NativeColumnBase<TItem> column) =>
        !ReferenceEquals(sortColumn, column) ? null : descending ? "descending" : "ascending";

    public void Dispose() => request?.Cancel();
}
EOF

write NativeModal.razor <<'EOF'
@* NativeModal: a dialog of the application with the Bootstrap markup (a component shown in a dialog: that component
   inside it): @bind-Visible, or @ref and Show() / Hide(); with buttons, its content and its buttons both named
   (<ChildContent>…</ChildContent><Footer>…</Footer>: Razor refuses plain content next to a named one); it takes the
   focus when it shows, Escape and its close button hide it.
   Written by blazor-native.sh scaffold; the application owns it. *@
@namespace __NS__
@using Microsoft.AspNetCore.Components.Web

@if (Visible)
{
    <div @ref="dialog" class="modal fade show d-block" tabindex="-1" role="dialog" aria-modal="true" aria-label="@Title" style="background-color: rgba(0, 0, 0, 0.5)" @onkeydown="OnKeyDownAsync">
        <div class="modal-dialog @DialogClass" role="document">
            <div class="modal-content">
                @if (!string.IsNullOrEmpty(Title))
                {
                    <div class="modal-header">
                        <h5 class="modal-title">@Title</h5>
                        <button type="button" class="btn-close" aria-label="Fermer" @onclick="Hide"></button>
                    </div>
                }
                <div class="modal-body">@ChildContent</div>
                @if (Footer is not null)
                {
                    <div class="modal-footer">@Footer</div>
                }
            </div>
        </div>
    </div>
}

@code {
    [Parameter]
    public bool Visible { get; set; }

    [Parameter]
    public EventCallback<bool> VisibleChanged { get; set; }

    [Parameter]
    public string? Title { get; set; }

    /// <summary>Its size: sm, lg or xl.</summary>
    [Parameter]
    public string? Size { get; set; }

    [Parameter]
    public RenderFragment? ChildContent { get; set; }

    /// <summary>Its buttons.</summary>
    [Parameter]
    public RenderFragment? Footer { get; set; }

    private ElementReference dialog;
    private bool focused;

    private string DialogClass => string.IsNullOrEmpty(Size) ? string.Empty : "modal-" + Size;

    public Task Show() => SetVisibleAsync(true);

    public Task Hide() => SetVisibleAsync(false);

    protected override async Task OnAfterRenderAsync(bool firstRender)
    {
        // the focus in the dialog when it shows: Escape and Tab start there
        if (Visible && !focused)
        {
            focused = true;
            await dialog.FocusAsync();
        }
        else if (!Visible)
        {
            focused = false;
        }
    }

    private async Task SetVisibleAsync(bool visible)
    {
        if (Visible == visible)
        {
            return;
        }

        Visible = visible;
        await VisibleChanged.InvokeAsync(visible);
        StateHasChanged();
    }

    private Task OnKeyDownAsync(KeyboardEventArgs e) => e.Key == "Escape" ? Hide() : Task.CompletedTask;
}
EOF

write NativeDialogService.cs <<'EOF'
using System;
using System.Threading.Tasks;

namespace __NS__;

// The questions and the messages of the application in a dialog: ConfirmAsync gives the user's answer, AlertAsync
// waits for its OK. They show in the
// NativeDialogHost of the layout. Registered once in Program.cs: builder.Services.AddScoped<NativeDialogService>();
// <NativeDialogHost /> once in the layout. Written by blazor-native.sh scaffold; the application owns it.
public sealed class NativeDialogService
{
    private int hosts;

    internal event Action? Changed;

    internal NativeDialogRequest? Current { get; private set; }

    /// <summary>Asks the user: true when they confirm.</summary>
    public Task<bool> ConfirmAsync(string message, string title = "Confirmation", string confirmText = "Confirmer", string cancelText = "Annuler") =>
        Open(new NativeDialogRequest(message, title, confirmText, cancelText));

    /// <summary>Tells the user, with one button.</summary>
    public Task AlertAsync(string message, string title = "Information", string okText = "OK") =>
        Open(new NativeDialogRequest(message, title, okText, null));

    internal void Attach() => hosts++;

    internal void Detach() => hosts--;

    internal void Answer(bool confirmed)
    {
        var request = Current;
        Current = null;
        request?.Answer(confirmed);
        Changed?.Invoke();
    }

    private Task<bool> Open(NativeDialogRequest request)
    {
        if (hosts <= 0)
        {
            // without a host, the question would wait for ever
            throw new InvalidOperationException("No NativeDialogHost shows the dialogs: add <NativeDialogHost /> to the layout (to the page itself when only the page is interactive), and render it in the tests of the page.");
        }

        Current?.Answer(false);
        Current = request;
        Changed?.Invoke();
        return request.Task;
    }
}

internal sealed class NativeDialogRequest
{
    private readonly TaskCompletionSource<bool> completion = new(TaskCreationOptions.RunContinuationsAsynchronously);

    public NativeDialogRequest(string message, string title, string confirmText, string? cancelText)
    {
        Message = message;
        Title = title;
        ConfirmText = confirmText;
        CancelText = cancelText;
    }

    public string Message { get; }

    public string Title { get; }

    public string ConfirmText { get; }

    /// <summary>null for a message (one button).</summary>
    public string? CancelText { get; }

    public Task<bool> Task => completion.Task;

    public void Answer(bool confirmed) => completion.TrySetResult(confirmed);
}
EOF

write NativeDialogHost.razor <<'EOF'
@* NativeDialogHost: where the questions and the messages of NativeDialogService show, once in the layout; it takes the
   focus, Escape answers no (OK for a message). Written by blazor-native.sh scaffold; the application owns it. *@
@namespace __NS__
@using Microsoft.AspNetCore.Components.Web
@implements IDisposable
@inject NativeDialogService Dialogs

@if (Dialogs.Current is { } request)
{
    <div @ref="dialog" class="modal fade show d-block" tabindex="-1" role="dialog" aria-modal="true" aria-label="@request.Title" style="background-color: rgba(0, 0, 0, 0.5)" @onkeydown="OnKeyDown">
        <div class="modal-dialog" role="document">
            <div class="modal-content">
                <div class="modal-header">
                    <h5 class="modal-title">@request.Title</h5>
                </div>
                <div class="modal-body">
                    <p class="mb-0">@request.Message</p>
                </div>
                <div class="modal-footer">
                    @if (request.CancelText is not null)
                    {
                        <button type="button" class="btn btn-secondary" @onclick="() => Dialogs.Answer(false)">@request.CancelText</button>
                    }
                    <button type="button" class="btn btn-primary" @onclick="() => Dialogs.Answer(true)">@request.ConfirmText</button>
                </div>
            </div>
        </div>
    </div>
}

@code {
    private ElementReference dialog;
    private object? focusedFor;

    protected override void OnInitialized()
    {
        Dialogs.Changed += OnChanged;
        Dialogs.Attach();
    }

    protected override async Task OnAfterRenderAsync(bool firstRender)
    {
        if (Dialogs.Current is { } request && !ReferenceEquals(request, focusedFor))
        {
            focusedFor = request;
            await dialog.FocusAsync();
        }
    }

    private void OnChanged() => _ = InvokeAsync(StateHasChanged);

    private void OnKeyDown(KeyboardEventArgs e)
    {
        if (e.Key == "Escape" && Dialogs.Current is { } request)
        {
            Dialogs.Answer(request.CancelText is null);
        }
    }

    public void Dispose()
    {
        Dialogs.Changed -= OnChanged;
        Dialogs.Detach();
    }
}
EOF

write NativeToastService.cs <<'EOF'
using System;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace __NS__;

// The short messages of the application: Success, Info, Warning, Error, shown by the NativeToastHost of the layout. Registered once in Program.cs:
// builder.Services.AddScoped<NativeToastService>(); <NativeToastHost /> once in the layout.
// Written by blazor-native.sh scaffold; the application owns it.
public enum NativeToastLevel
{
    Info,
    Success,
    Warning,
    Error,
}

public sealed class NativeToastService
{
    private readonly List<NativeToast> messages = new();

    internal event Action? Changed;

    internal IReadOnlyList<NativeToast> Messages => messages;

    public Task Show(string message, NativeToastLevel level = NativeToastLevel.Info, string? title = null)
    {
        messages.Add(new NativeToast(Guid.NewGuid(), message, level, title));
        Changed?.Invoke();
        return Task.CompletedTask;
    }

    public Task Success(string message, string? title = null) => Show(message, NativeToastLevel.Success, title);

    public Task Info(string message, string? title = null) => Show(message, NativeToastLevel.Info, title);

    public Task Warning(string message, string? title = null) => Show(message, NativeToastLevel.Warning, title);

    public Task Error(string message, string? title = null) => Show(message, NativeToastLevel.Error, title);

    internal void Close(Guid id)
    {
        if (messages.RemoveAll(m => m.Id == id) > 0)
        {
            Changed?.Invoke();
        }
    }
}

internal sealed record NativeToast(Guid Id, string Text, NativeToastLevel Level, string? Title);
EOF

write NativeToastHost.razor <<'EOF'
@* NativeToastHost: where the messages of NativeToastService show, once in the layout; each one closes by its button,
   or by itself after DelaySeconds (0: never). Written by blazor-native.sh scaffold; the application owns it. *@
@namespace __NS__
@using System.Threading
@using Microsoft.AspNetCore.Components.Web
@implements IDisposable
@inject NativeToastService Toasts

<div class="toast-container position-fixed top-0 end-0 p-3">
    @foreach (var toast in Toasts.Messages)
    {
        <div @key="toast.Id" class="toast show align-items-center @LevelClass(toast.Level) border-0" role="status" aria-live="polite" aria-atomic="true">
            <div class="d-flex">
                <div class="toast-body">
                    @if (!string.IsNullOrEmpty(toast.Title))
                    {
                        <strong class="me-1">@toast.Title</strong>
                    }
                    @toast.Text
                </div>
                <button type="button" class="btn-close btn-close-white me-2 m-auto" aria-label="Fermer" @onclick="() => Toasts.Close(toast.Id)"></button>
            </div>
        </div>
    }
</div>

@code {
    /// <summary>A message closes by itself after these seconds (0: only by its button).</summary>
    [Parameter]
    public int DelaySeconds { get; set; } = 5;

    private readonly CancellationTokenSource closing = new();
    private readonly HashSet<Guid> timed = new();

    protected override void OnInitialized() => Toasts.Changed += OnChanged;

    private void OnChanged()
    {
        if (DelaySeconds > 0)
        {
            foreach (var toast in Toasts.Messages.Where(t => timed.Add(t.Id)).ToList())
            {
                _ = CloseLaterAsync(toast.Id);
            }
        }

        _ = InvokeAsync(StateHasChanged);
    }

    private async Task CloseLaterAsync(Guid id)
    {
        try
        {
            await Task.Delay(TimeSpan.FromSeconds(DelaySeconds), closing.Token);
            await InvokeAsync(() => Toasts.Close(id));
        }
        catch (OperationCanceledException)
        {
            // the host left the page
        }
    }

    private static string LevelClass(NativeToastLevel level) => level switch
    {
        NativeToastLevel.Success => "text-bg-success",
        NativeToastLevel.Warning => "text-bg-warning",
        NativeToastLevel.Error => "text-bg-danger",
        _ => "text-bg-primary",
    };

    public void Dispose()
    {
        Toasts.Changed -= OnChanged;
        closing.Cancel();
        closing.Dispose();
    }
}
EOF

write NativeFieldCssClassProvider.cs <<'EOF'
using System.Linq;
using Microsoft.AspNetCore.Components.Forms;

namespace __NS__;

// The Bootstrap classes of a field of an EditForm: is-invalid once its validation failed, is-valid once the user
// changed it. In the page: editContext.SetFieldCssClassProvider(new
// NativeFieldCssClassProvider()); and .validation-message styled as .invalid-feedback in the CSS of the application.
// Written by blazor-native.sh scaffold; the application owns it.
public sealed class NativeFieldCssClassProvider : FieldCssClassProvider
{
    public override string GetFieldCssClass(EditContext editContext, in FieldIdentifier fieldIdentifier)
    {
        var isValid = !editContext.GetValidationMessages(fieldIdentifier).Any();
        if (editContext.IsModified(fieldIdentifier))
        {
            return isValid ? "is-valid" : "is-invalid";
        }

        return isValid ? string.Empty : "is-invalid";
    }
}
EOF

# the @using of the components, in the _Imports.razor of their folder or the nearest one above it
imports=""
for f in "$project/Components/_Imports.razor" "$project/_Imports.razor"; do
  [ -f "$f" ] && { imports=$f; break; }
done
if [ -n "$imports" ]; then
  if grep -q -x -F "@using $nsn" "$imports"; then
    echo "IMPORTS: $imports has @using $nsn already"
  else
    [ -n "$(tail -c 1 "$imports")" ] && echo >> "$imports"
    printf '@using %s\n' "$nsn" >> "$imports"
    echo "IMPORTS: @using $nsn added to $imports"
  fi
else
  echo "IMPORTS: no _Imports.razor in $project: add @using $nsn to the pages that use these components"
fi
echo "NEXT: the pages with questions or messages need, once: builder.Services.AddScoped<NativeDialogService>(); builder.Services.AddScoped<NativeToastService>(); in Program.cs, and <NativeDialogHost /> <NativeToastHost /> in the layout (MainLayout.razor; in the page itself when only the page is interactive). Their tests register the same services in their context and render the host with the page."
exit 0
