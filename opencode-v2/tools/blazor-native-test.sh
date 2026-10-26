#!/bin/sh
# The replacement of Blazorise by native Razor, for real, as /go runs it: the .NET SDKs 10 and 8, the real packages
# (Blazorise 2.2.2, bUnit, coverlet), the pack's scripts and the code of the skill blazorise as it is written (its page
# on the DataGrid, its test helper, the tests of its page, its native page, the language of the DataGrid). For each
# target framework:
#   - the analyst: blazor-native.sh inventory (the page, the packages, the registration, the links, the plan)
#   - fortify.sh prereq --tests: no bUnit yet; test-guardian.sh setup --components creates the unit test project with
#     bUnit (the developer agreed), then builds it
#   - before the change (the test-guardian, mission « filet »): deps of the page, its coverage and its net before any
#     test (THIN), the tests of what its users see written on the Blazorise DataGrid, green twice, its net measured by
#     coverlet on the .razor page (OK), test-lint, tests-only, sealed
#   - the coder, first step: blazor-native.sh scaffold writes the native components; they build next to Blazorise
#     (none of their names meets one of its)
#   - the coder, the page: rewritten on NativeGrid; the sealed tests unchanged, green twice, the net kept, nothing lost
#   - the native components themselves, through a page that uses them all, with bUnit: the data of a server, its
#     default sort, its pages, the sort of each column, a column shown under a condition, a click on a row and the
#     selected row, the text of an empty list, a dialog (@bind-Visible, Escape, its buttons), the questions and the
#     messages of NativeDialogService (yes, no, Escape, OK, no host), the toasts (their level, their button, their
#     delay), the Bootstrap classes of a field
#   - the last step: every Blazorise package, registration, using and link removed, the test helper without it;
#     blazor-native.sh check says GONE, the build and every test green
# Needs dotnet (the CI installs the SDKs 10 and 8) and the NuGet feed of the machine (nuget.org in the CI); no
# repository and no setting of this machine is changed. Usage, from opencode-v2/: sh tools/blazor-native-test.sh [<shell>]
SHELL_UNDER_TEST=${1:-sh}
pack=$(cd "$(dirname "$0")/.." && pwd)
scripts="$pack/scripts"
command -v dotnet >/dev/null 2>&1 || { echo "blazor-native-test: dotnet is not on the PATH of this machine"; exit 2; }
work=$(mktemp -d "${TMPDIR:-/tmp}/blazor-native-test.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/tmp"
TMPDIR="$work/tmp"
MSBUILDDISABLENODEREUSE=1 DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1 DOTNET_CLI_UI_LANGUAGE=en
export TMPDIR MSBUILDDISABLENODEREUSE DOTNET_CLI_TELEMETRY_OPTOUT DOTNET_NOLOGO DOTNET_CLI_UI_LANGUAGE
GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$work/gitconfig"
GIT_AUTHOR_NAME=dev GIT_AUTHOR_EMAIL=dev@example.com GIT_COMMITTER_NAME=dev GIT_COMMITTER_EMAIL=dev@example.com
export GIT_CONFIG_NOSYSTEM GIT_CONFIG_GLOBAL GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
printf '[init]\n\tdefaultBranch = develop\n' > "$GIT_CONFIG_GLOBAL"
BLAZORISE=2.2.2
echo "blazor-native-test: SDKs $(dotnet --list-sdks | awk '{ printf "%s%s", sep, $1; sep = ", " }')"

pass=0
fail=0
check() {
  # check <name> <expected exit: 0|1|any> <grep pattern of the output> [<pattern that must not appear>]
  name=$1 want=$2 pattern=$3 absent=$4
  ok=1
  case "$want" in
    any) ;;
    0) [ "$status" -eq 0 ] || ok=0 ;;
    *) [ "$status" -ne 0 ] || ok=0 ;;
  esac
  printf '%s\n' "$out" | grep -qE -- "$pattern" || ok=0
  [ -n "$absent" ] && printf '%s\n' "$out" | grep -qE -- "$absent" && ok=0
  if [ "$ok" -eq 1 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: $name (exit $status)"
    printf '%s\n' "$out" | sed 's/^/    /' | tail -n 40
  fi
  return "$((1 - ok))"
}
verdict() {
  # verdict <name> <status of the condition>
  if [ "$2" -eq 0 ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL: $1"; fi
}
run() {
  script=$1
  shift
  out=$("$SHELL_UNDER_TEST" "$scripts/$script" "$@" 2>&1)
  status=$?
}
commit() { git add -A >/dev/null 2>&1 && git commit -q -m "$1" >/dev/null 2>&1; }
note() { echo "NOTE: $*"; }

# The code blocks of the skill, in order: 1 the helper of the page tests, 2 the orders page on the DataGrid, 3 the
# tests of the orders page, 4 the orders page in native Razor, 5 the language of Blazorise, 6 the shared texts of the
# DataGrid
blocks="$work/blocks"
mkdir -p "$blocks"
awk -v dir="$blocks" '
  /^ *```[a-z]+$/ { n++; inblock = 1; file = dir "/" n; next }
  /^ *```$/ && inblock { inblock = 0; close(file); next }
  inblock { sub(/^   /, ""); print > file }' "$pack/skills/blazorise/SKILL.md"
if [ -s "$blocks/6" ] && [ ! -e "$blocks/7" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL: the skill blazorise has not its 6 code blocks"; ls "$blocks"; fi

# The rendered markup of the page, after a failure: what the DataGrid or NativeGrid really wrote
markup() {
  [ -s "$1" ] || return 0
  echo "    markup of the page ($2):"
  tr -s ' \t' ' ' < "$1" | sed -e 's/></>\n</g' | grep -v '^[[:space:]]*$' | head -n 40 | sed 's/^/    /'
}
dump_markup() {
  # dump_markup <file>: renders the page once with the data of the tests, and writes its markup (a test of its own,
  # removed right after: it is no test of the page)
  cat > tests/Web.UnitTests/MarkupDump.cs <<'EOF'
using Bunit;
using Microsoft.Extensions.DependencyInjection;
using Web.Components.Pages;
using Web.Data;
using Xunit;

namespace Web.UnitTests;

public class MarkupDump
{
    [Fact]
    public async Task Dump()
    {
        var orders = Enumerable.Range(1, 12).Select(i => new Order($"CMD-{i:00}", new DateTime(2026, 1, i), 10.5m * i)).ToList();
        await using var ctx = PageTest.Context();
        ctx.Services.AddSingleton<IOrderSource>(new Fixed(orders));
        var cut = ctx.Render<Orders>();
        try { cut.WaitForState(() => cut.FindAll("tbody tr").Count > 0, TimeSpan.FromSeconds(5)); }
        finally { File.WriteAllText(Environment.GetEnvironmentVariable("MARKUP_DUMP")!, cut.Markup); }
    }

    private sealed class Fixed(IReadOnlyList<Order> orders) : IOrderSource
    {
        public IReadOnlyList<Order> All() => orders;
    }
}
EOF
  MARKUP_DUMP=$1 dotnet test tests/Web.UnitTests/Web.UnitTests.csproj --filter FullyQualifiedName~MarkupDump --nologo -v q > "$1.log" 2>&1
  rm -f tests/Web.UnitTests/MarkupDump.cs
}

# The methods coverlet reports for the page (the classes whose file is the .razor page)
razor_methods() {
  report=$(find "$1" -name '*.cobertura.xml' 2>/dev/null | head -n 1)
  [ -n "$report" ] || { echo "no report"; return 0; }
  awk '/<class / { on = ($0 ~ /filename="[^"]*Orders\.razor"/); if (on && match($0, /filename="[^"]*"/)) file = substr($0, RSTART + 10, RLENGTH - 11); next }
       on && /<method / { if (match($0, / name="[^"]*"/)) m[substr($0, RSTART + 7, RLENGTH - 8)] = 1 }
       END { for (k in m) out = out (out == "" ? "" : ", ") k; printf "%s (%s)\n", (out == "" ? "none" : out), (file == "" ? "no class of Orders.razor" : file) }' "$report" |
    sed 's/&lt;/</g; s/&gt;/>/g'
  # no class of the page: what coverlet names instead (a generated file, another path)
  grep -q 'filename="[^"]*Orders\.razor"' "$report" ||
    echo "; the files of the report that name Orders: $(grep -o 'filename="[^"]*Orders[^"]*"' "$report" | sort -u | head -n 5 | tr '\n' ' ')"
}

# A page that uses every native component of blazor-native.sh scaffold, and its bUnit tests: what the components do,
# for real (a fixture of this test, not a page of the story)
native_demo() {
  cat > src/Web/Components/Pages/NativeDemo.razor <<'EOF'
@page "/native-demo"
@inject NativeDialogService Dialogs
@inject NativeToastService Toasts

<NativeGrid @ref="grid" TItem="Order" ItemsProvider="@LoadAsync" ShowPager PageSize="3" @bind-SelectedItem="selected" RowClicked="@(o => clicked = o.Number)">
    <NativeColumn Field="@(o => o.Number)" Title="Numéro" />
    <NativeColumn Field="@(o => o.Date)" Title="Date" Format="{0:dd/MM/yyyy}" IsDefaultSort Descending />
    @if (showTotal)
    {
        <NativeColumn Field="@(o => o.Total)" Title="Total" Format="N2" Sortable="false" />
    }
    <NativeTemplateColumn Title="Actions" SortBy="@(o => o.Total)">
        <button type="button" class="btn btn-sm btn-danger" @onclick="() => DeleteAsync(context)" @onclick:stopPropagation="true">Supprimer @context.Number</button>
    </NativeTemplateColumn>
</NativeGrid>
<NativeGrid Items="@none" EmptyText="Aucune commande">
    <NativeColumn Field="@(o => o.Number)" Title="Numéro" />
</NativeGrid>
<p id="clicked">@clicked</p>
<p id="selected">@selected?.Number</p>
<p id="answer">@answer</p>
<p id="editing">@editing</p>
<button type="button" @onclick="() => showTotal = !showTotal">Colonne total</button>
<button type="button" @onclick="() => editing = true">Modifier</button>
<button type="button" @onclick="InformAsync">Informer</button>
<NativeModal @bind-Visible="editing" Title="Modifier la commande">
    <ChildContent>
        <p>Le formulaire</p>
    </ChildContent>
    <Footer>
        <button type="button" class="btn btn-secondary" @onclick="() => editing = false">Fermer</button>
    </Footer>
</NativeModal>

@code {
    private readonly List<Order> orders = Enumerable.Range(1, 7).Select(i => new Order($"CMD-{i:00}", new DateTime(2026, 1, i), 10m * i)).ToList();
    private readonly List<Order> none = new();
    private NativeGrid<Order>? grid;
    private Order? selected;
    private string? clicked;
    private string? answer;
    private bool showTotal = true;
    private bool editing;

    public List<NativeGridRequest> Requests { get; } = new();

    private ValueTask<NativeGridResult<Order>> LoadAsync(NativeGridRequest request)
    {
        Requests.Add(request);
        IEnumerable<Order> rows = request.SortBy switch
        {
            "Number" => request.Descending ? orders.OrderByDescending(o => o.Number) : orders.OrderBy(o => o.Number),
            "Date" => request.Descending ? orders.OrderByDescending(o => o.Date) : orders.OrderBy(o => o.Date),
            "Actions" => request.Descending ? orders.OrderByDescending(o => o.Total) : orders.OrderBy(o => o.Total),
            _ => orders,
        };
        var page = rows.Skip(request.StartIndex).Take(request.Count).ToList();
        return ValueTask.FromResult(new NativeGridResult<Order>(page, orders.Count));
    }

    private async Task DeleteAsync(Order order)
    {
        if (!await Dialogs.ConfirmAsync($"Supprimer {order.Number} ?"))
        {
            answer = "gardée";
            return;
        }

        orders.Remove(order);
        answer = "supprimée";
        await Toasts.Success($"{order.Number} supprimée");
        if (grid is not null)
        {
            await grid.RefreshAsync();
        }
    }

    private async Task InformAsync()
    {
        await Dialogs.AlertAsync("Rien à signaler");
        answer = "lu";
    }
}
EOF
  cat > tests/Web.UnitTests/NativeComponentsTests.cs <<'EOF'
using AngleSharp.Dom;
using Bunit;
using Microsoft.AspNetCore.Components.Forms;
using Microsoft.AspNetCore.Components.Web;
using Microsoft.Extensions.DependencyInjection;
using Web.Components.Native;
using Web.Components.Pages;
using Web.Data;
using Xunit;

namespace Web.UnitTests;

// The native components blazor-native.sh writes, through a page that uses them all
public class NativeComponentsTests
{
    [Fact]
    public async Task Grid_FirstLoad_AsksOnePageSortedByTheDefaultColumn()
    {
        await using var ctx = Context();
        var cut = ctx.Render<NativeDemo>();

        cut.WaitForAssertion(() => Assert.Equal(new[] { "CMD-07", "CMD-06", "CMD-05" }, Numbers(cut)));
        var request = Assert.Single(cut.Instance.Requests);
        Assert.Equal((0, 3, "Date", true), (request.StartIndex, request.Count, request.SortBy, request.Descending));
        Assert.Equal(new[] { "Numéro", "Date", "Total", "Actions" }, Headers(cut));
        Assert.Equal("descending", Header(cut, "Date").GetAttribute("aria-sort"));
        Assert.Null(Header(cut, "Total").QuerySelector("button"));
        Assert.Equal(new[] { "CMD-07", "07/01/2026", "70,00", "Supprimer CMD-07" }, Cells(cut, 0));
        Assert.Equal("Page 1 sur 3 · 7 éléments", cut.Find("nav span").TextContent.Trim());
        Assert.Equal("Aucune commande", cut.FindAll("table")[1].QuerySelector("tbody td")!.TextContent.Trim());
    }

    [Fact]
    public async Task Grid_Pages_AskTheServerForEachPage()
    {
        await using var ctx = Context();
        var cut = ctx.Render<NativeDemo>();
        cut.WaitForAssertion(() => Assert.Equal(3, Numbers(cut).Length));

        await Button(cut, "Suivante").ClickAsync();
        cut.WaitForAssertion(() => Assert.Equal(new[] { "CMD-04", "CMD-03", "CMD-02" }, Numbers(cut)));
        Assert.Equal(3, cut.Instance.Requests[^1].StartIndex);

        await Button(cut, "Dernière").ClickAsync();
        cut.WaitForAssertion(() => Assert.Equal(new[] { "CMD-01" }, Numbers(cut)));
        Assert.Equal("Page 3 sur 3 · 7 éléments", cut.Find("nav span").TextContent.Trim());
        Assert.True(Button(cut, "Suivante").HasAttribute("disabled"));
    }

    [Fact]
    public async Task Grid_ClickOnTitles_SortsByTheirColumn_TheTemplateOneByItsSortBy()
    {
        await using var ctx = Context();
        var cut = ctx.Render<NativeDemo>();
        cut.WaitForAssertion(() => Assert.Equal(3, Numbers(cut).Length));

        await SortByAsync(cut, "Numéro");
        cut.WaitForAssertion(() => Assert.Equal(new[] { "CMD-01", "CMD-02", "CMD-03" }, Numbers(cut)));
        Assert.Equal(("Number", false), (cut.Instance.Requests[^1].SortBy, cut.Instance.Requests[^1].Descending));
        Assert.Equal("ascending", Header(cut, "Numéro").GetAttribute("aria-sort"));
        Assert.Null(Header(cut, "Date").GetAttribute("aria-sort"));

        await SortByAsync(cut, "Numéro");
        cut.WaitForAssertion(() => Assert.Equal("CMD-07", Numbers(cut)[0]));

        await SortByAsync(cut, "Actions");
        cut.WaitForAssertion(() => Assert.Equal("CMD-01", Numbers(cut)[0]));
        Assert.Equal(("Actions", false), (cut.Instance.Requests[^1].SortBy, cut.Instance.Requests[^1].Descending));
    }

    [Fact]
    public async Task Grid_ColumnUnderACondition_LeavesAndComesBackInItsPlaceAtOnce()
    {
        await using var ctx = Context();
        var cut = ctx.Render<NativeDemo>();
        cut.WaitForAssertion(() => Assert.Equal(3, Numbers(cut).Length));

        await Button(cut, "Colonne total").ClickAsync();
        Assert.Equal(new[] { "Numéro", "Date", "Actions" }, Headers(cut));
        Assert.Equal(new[] { "CMD-07", "07/01/2026", "Supprimer CMD-07" }, Cells(cut, 0));

        await Button(cut, "Colonne total").ClickAsync();
        Assert.Equal(new[] { "Numéro", "Date", "Total", "Actions" }, Headers(cut));
        Assert.Single(cut.Instance.Requests);
    }

    [Fact]
    public async Task Grid_ClickOnARow_SelectsIt()
    {
        await using var ctx = Context();
        var cut = ctx.Render<NativeDemo>();
        cut.WaitForAssertion(() => Assert.Equal(3, Numbers(cut).Length));

        await Rows(cut)[1].ClickAsync();

        Assert.Equal("CMD-06", cut.Find("#clicked").TextContent);
        Assert.Equal("CMD-06", cut.Find("#selected").TextContent);
        Assert.Contains("table-active", Rows(cut)[1].ClassList);
        Assert.DoesNotContain("table-active", Rows(cut)[0].ClassList);
    }

    [Fact]
    public async Task Dialog_Confirmed_DeletesTheOrder_AndAToastSaysIt()
    {
        await using var ctx = Context();
        var dialogs = ctx.Render<NativeDialogHost>();
        var toasts = ctx.Render<NativeToastHost>(p => p.Add(h => h.DelaySeconds, 0));
        var cut = ctx.Render<NativeDemo>();
        cut.WaitForAssertion(() => Assert.Equal(3, Numbers(cut).Length));

        var deleting = Button(cut, "Supprimer CMD-07").ClickAsync();
        dialogs.WaitForAssertion(() => Assert.Equal("Supprimer CMD-07 ?", dialogs.Find(".modal-body").TextContent.Trim()));
        Assert.Equal(new[] { "Annuler", "Confirmer" }, dialogs.FindAll("button").Select(b => b.TextContent.Trim()).ToArray());
        await dialogs.Find("button.btn-primary").ClickAsync();
        await deleting;

        cut.WaitForAssertion(() => Assert.Equal(new[] { "CMD-06", "CMD-05", "CMD-04" }, Numbers(cut)));
        Assert.Equal("supprimée", cut.Find("#answer").TextContent);
        Assert.Equal(string.Empty, cut.Find("#clicked").TextContent);
        Assert.Equal("Page 1 sur 2 · 6 éléments", cut.Find("nav span").TextContent.Trim());
        dialogs.WaitForAssertion(() => Assert.Empty(dialogs.FindAll(".modal")));
        toasts.WaitForAssertion(() => Assert.Contains("CMD-07 supprimée", toasts.Find(".toast.text-bg-success").TextContent));

        await toasts.Find(".toast .btn-close").ClickAsync();
        toasts.WaitForAssertion(() => Assert.Empty(toasts.FindAll(".toast")));
    }

    [Fact]
    public async Task Dialog_Cancelled_KeepsTheOrder()
    {
        await using var ctx = Context();
        var dialogs = ctx.Render<NativeDialogHost>();
        var toasts = ctx.Render<NativeToastHost>(p => p.Add(h => h.DelaySeconds, 0));
        var cut = ctx.Render<NativeDemo>();
        cut.WaitForAssertion(() => Assert.Equal(3, Numbers(cut).Length));

        var deleting = Button(cut, "Supprimer CMD-07").ClickAsync();
        dialogs.WaitForAssertion(() => Assert.Single(dialogs.FindAll(".modal")));
        await dialogs.Find("button.btn-secondary").ClickAsync();
        await deleting;

        cut.WaitForAssertion(() => Assert.Equal("gardée", cut.Find("#answer").TextContent));
        Assert.Equal("CMD-07", Numbers(cut)[0]);
        Assert.Empty(toasts.FindAll(".toast"));
    }

    [Fact]
    public async Task Dialog_Escape_AnswersNo()
    {
        await using var ctx = Context();
        var dialogs = ctx.Render<NativeDialogHost>();
        var cut = ctx.Render<NativeDemo>();
        cut.WaitForAssertion(() => Assert.Equal(3, Numbers(cut).Length));

        var deleting = Button(cut, "Supprimer CMD-07").ClickAsync();
        dialogs.WaitForAssertion(() => Assert.Single(dialogs.FindAll(".modal")));
        await dialogs.Find(".modal").KeyDownAsync(new KeyboardEventArgs { Key = "Escape" });
        await deleting;

        cut.WaitForAssertion(() => Assert.Equal("gardée", cut.Find("#answer").TextContent));
        dialogs.WaitForAssertion(() => Assert.Empty(dialogs.FindAll(".modal")));
    }

    [Fact]
    public async Task Dialog_Message_HasOneButton()
    {
        await using var ctx = Context();
        var dialogs = ctx.Render<NativeDialogHost>();
        var cut = ctx.Render<NativeDemo>();

        var informing = Button(cut, "Informer").ClickAsync();
        dialogs.WaitForAssertion(() => Assert.Equal(new[] { "OK" }, dialogs.FindAll("button").Select(b => b.TextContent.Trim()).ToArray()));
        Assert.Equal("Rien à signaler", dialogs.Find(".modal-body").TextContent.Trim());
        await dialogs.Find("button").ClickAsync();
        await informing;

        cut.WaitForAssertion(() => Assert.Equal("lu", cut.Find("#answer").TextContent));
    }

    [Fact]
    public async Task Dialog_WithoutHost_SaysWhatIsMissing()
    {
        await using var ctx = Context();
        var dialogs = ctx.Services.GetRequiredService<NativeDialogService>();

        var error = Assert.Throws<InvalidOperationException>(() => { _ = dialogs.ConfirmAsync("Supprimer ?"); });

        Assert.Contains("NativeDialogHost", error.Message);
    }

    [Fact]
    public async Task Modal_ShowsBoundToItsField_HidesByEscapeItsCloseButtonOrItsFooter()
    {
        await using var ctx = Context();
        var cut = ctx.Render<NativeDemo>();

        await Button(cut, "Modifier").ClickAsync();
        Assert.Equal("Modifier la commande", cut.Find(".modal-title").TextContent);
        Assert.Equal("Le formulaire", cut.Find(".modal-body").TextContent.Trim());
        Assert.Equal("True", cut.Find("#editing").TextContent);
        await cut.Find(".modal").KeyDownAsync(new KeyboardEventArgs { Key = "Escape" });
        Assert.Empty(cut.FindAll(".modal"));
        Assert.Equal("False", cut.Find("#editing").TextContent);

        await Button(cut, "Modifier").ClickAsync();
        await cut.Find(".modal .btn-close").ClickAsync();
        Assert.Empty(cut.FindAll(".modal"));
        Assert.Equal("False", cut.Find("#editing").TextContent);

        await Button(cut, "Modifier").ClickAsync();
        await cut.Find(".modal-footer button").ClickAsync();
        Assert.Empty(cut.FindAll(".modal"));
    }

    [Fact]
    public async Task Toast_ShowsItsLevelAndTitle_ClosesByItselfAfterItsDelay()
    {
        await using var ctx = Context();
        var host = ctx.Render<NativeToastHost>(p => p.Add(h => h.DelaySeconds, 1));
        var toasts = ctx.Services.GetRequiredService<NativeToastService>();

        await host.InvokeAsync(() => toasts.Error("Échec de l'envoi", "Commande"));

        host.WaitForAssertion(() => Assert.Contains("Échec de l'envoi", host.Find(".toast.text-bg-danger").TextContent));
        Assert.Equal("Commande", host.Find(".toast strong").TextContent);
        host.WaitForAssertion(() => Assert.Empty(host.FindAll(".toast")), TimeSpan.FromSeconds(10));
    }

    [Fact]
    public void FieldCssClass_InvalidOnceItsValidationFailed_ValidOnceChanged()
    {
        var edit = new EditContext(new Order("CMD-01", new DateTime(2026, 1, 1), 10m));
        var field = edit.Field(nameof(Order.Number));
        var provider = new NativeFieldCssClassProvider();
        var messages = new ValidationMessageStore(edit);

        Assert.Equal(string.Empty, provider.GetFieldCssClass(edit, field));
        messages.Add(field, "Le numéro est obligatoire");
        Assert.Equal("is-invalid", provider.GetFieldCssClass(edit, field));
        messages.Clear();
        edit.NotifyFieldChanged(field);
        Assert.Equal("is-valid", provider.GetFieldCssClass(edit, field));
    }

    private static BunitContext Context()
    {
        var ctx = PageTest.Context();
        ctx.Services.AddSingleton<NativeDialogService>();
        ctx.Services.AddSingleton<NativeToastService>();
        return ctx;
    }

    private static IElement Grid(IRenderedComponent<NativeDemo> cut) => cut.FindAll("table")[0];

    private static IElement[] Rows(IRenderedComponent<NativeDemo> cut) => Grid(cut).QuerySelectorAll("tbody tr").ToArray();

    private static string[] Headers(IRenderedComponent<NativeDemo> cut) =>
        Grid(cut).QuerySelectorAll("thead th").Select(th => th.TextContent.Trim()).ToArray();

    private static IElement Header(IRenderedComponent<NativeDemo> cut, string title) =>
        Grid(cut).QuerySelectorAll("thead th").First(th => th.TextContent.Trim() == title);

    private static string[] Numbers(IRenderedComponent<NativeDemo> cut) =>
        Rows(cut).Select(tr => tr.QuerySelector("td")?.TextContent.Trim() ?? "").ToArray();

    private static string[] Cells(IRenderedComponent<NativeDemo> cut, int row) =>
        Rows(cut)[row].QuerySelectorAll("td").Select(td => td.TextContent.Trim()).ToArray();

    private static IElement Button(IRenderedComponent<NativeDemo> cut, string text) =>
        cut.FindAll("button").First(b => b.TextContent.Trim() == text);

    private static Task SortByAsync(IRenderedComponent<NativeDemo> cut, string title) =>
        Header(cut, title).QuerySelector("button")!.ClickAsync();
}
EOF
}

scenario() {
  tfm=$1
  mkdir -p "$work/$tfm"
  cd "$work/$tfm" || exit 1
  git init -q .
  printf 'bin/\nobj/\n' > .gitignore
  mkdir -p src/Web/Components/Pages src/Web/Data
  cat > src/Web/Web.csproj <<EOF
<Project Sdk="Microsoft.NET.Sdk.Web">
  <PropertyGroup>
    <TargetFramework>$tfm</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Blazorise.Bootstrap5" Version="$BLAZORISE" />
    <PackageReference Include="Blazorise.Icons.FontAwesome" Version="$BLAZORISE" />
    <PackageReference Include="Blazorise.DataGrid" Version="$BLAZORISE" />
  </ItemGroup>
</Project>
EOF
  cat > src/Web/Program.cs <<'EOF'
using Blazorise;
using Blazorise.Bootstrap5;
using Blazorise.Icons.FontAwesome;
using Web.Components;
using Web.Data;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddRazorComponents().AddInteractiveServerComponents();
builder.Services.AddBlazorise(options => options.Immediate = true).AddBootstrap5Providers().AddFontAwesomeIcons();
builder.Services.AddSingleton<OrdersDb>();
builder.Services.AddScoped<IOrderSource, OrderSource>();
var app = builder.Build();
app.UseStaticFiles();
app.UseAntiforgery();
app.MapRazorComponents<App>().AddInteractiveServerRenderMode();
app.Run();
EOF
  cat > src/Web/Components/_Imports.razor <<'EOF'
@using Microsoft.AspNetCore.Components.Routing
@using Microsoft.AspNetCore.Components.Web
@using static Microsoft.AspNetCore.Components.Web.RenderMode
@using Web.Components
@using Web.Data
@using Blazorise
@using Blazorise.DataGrid
EOF
  cat > src/Web/Components/App.razor <<'EOF'
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="utf-8" />
    <base href="/" />
    <link rel="stylesheet" href="css/bootstrap.min.css" />
    <link href="_content/Blazorise/blazorise.css" rel="stylesheet" />
    <link href="_content/Blazorise.Bootstrap5/blazorise.bootstrap5.css" rel="stylesheet" />
    <HeadOutlet @rendermode="InteractiveServer" />
</head>
<body>
    <Routes @rendermode="InteractiveServer" />
    <script src="_framework/blazor.web.js"></script>
</body>
</html>
EOF
  cat > src/Web/Components/Routes.razor <<'EOF'
<Router AppAssembly="typeof(Program).Assembly">
    <Found Context="routeData">
        <RouteView RouteData="routeData" />
    </Found>
</Router>
EOF
  cat > src/Web/Data/Orders.cs <<'EOF'
namespace Web.Data;

public record Order(string Number, DateTime Date, decimal Total);

public interface IOrderSource
{
    IReadOnlyList<Order> All();
}

public class OrderSource(OrdersDb db) : IOrderSource
{
    public IReadOnlyList<Order> All() => db.Orders;
}

public class OrdersDb
{
    public List<Order> Orders { get; } = new();
}
EOF
  # the code of the skill: the language of Blazorise, its texts, the orders page on the DataGrid
  cp "$blocks/5" src/Web/Components/BlazoriseLanguage.razor
  cp "$blocks/6" src/Web/Components/GridTexts.cs
  cp "$blocks/2" src/Web/Components/Pages/Orders.razor
  commit "feat: the orders page on the Blazorise DataGrid"
  page=src/Web/Components/Pages/Orders.razor
  t=tests/Web.UnitTests/Web.UnitTests.csproj

  run build-test.sh --build-only src/Web/Web.csproj
  check "$tfm: the code of the skill builds against Blazorise $BLAZORISE" 0 '^BUILD: OK' || return 0
  # ---- the analyst: what uses Blazorise, the plan ----
  run blazor-native.sh inventory
  check "$tfm: inventory: the orders page, a grid" 0 '^PAGE: src/Web/Components/Pages/Orders\.razor — grid: DataGridColumn×3, DataGrid×1 — step 1$'
  check "$tfm: inventory: the packages and their version" 0 "^PACKAGE: Blazorise\\.Bootstrap5 $BLAZORISE, Blazorise\\.DataGrid $BLAZORISE, Blazorise\\.Icons\\.FontAwesome $BLAZORISE\$"
  check "$tfm: inventory: the registration, the links, the language service" 0 '^REGISTRATION: src/Web/Program\.cs:[0-9]+ builder\.Services\.AddBlazorise' 'UNKNOWN TAG'
  check "$tfm: inventory: the plan" 0 '^PLAN: a first step that writes the native components .*\(1 with a grid: NativeGrid\)'
  run fortify.sh prereq --tests
  check "$tfm: prereq: no test project, no bUnit" 0 '^PREREQ: COMPONENT TESTS: none'
  # the developer agreed: the unit test project, with bUnit
  run test-guardian.sh setup --components xunit "$page"
  check "$tfm: setup --components: the unit test project created with bUnit, built" 0 "^SETUP: $t created \\(xunit, $tfm\\), it references src/Web/Web\\.csproj; packages: .*bunit [0-9]+\\.[0-9.]+.*; build OK$" || return 0
  note "$tfm: $(printf '%s\n' "$out" | sed -n 's/.*packages: \(.*\); build OK$/\1/p')"
  commit "test: add the unit test project, with bUnit"
  run fortify.sh prereq --tests
  check "$tfm: prereq: the unit test project has bUnit now" 0 "^PREREQ: COMPONENT TESTS: bUnit in $t\$"

  # ---- before the change: the safety net of the page (the test-guardian, mission « filet ») ----
  run test-guardian.sh deps "$page"
  check "$tfm: deps of the page: the source of its orders" 0 '^DEPENDS: IOrderSource -> src/Web/Data/Orders\.cs$'
  run test-guardian.sh coverage F1-before "$t" "$page"
  check "$tfm: coverage of the page before its tests: none of its lines runs" 0 "no test in $t yet|^src/Web/Components/Pages/Orders\\.razor lines 0/[0-9]+ \\(0%\\)"
  run test-guardian.sh net F1-before "$page:OnInitialized" "$page:BuildRenderTree"
  check "$tfm: the net of the page before its tests: THIN" 0 '^SAFETY NET: THIN '
  note "$tfm, before the tests: $(printf '%s\n' "$out" | grep -E '^(NET|SAFETY NET):' | cut -c1-160 | tr '\n' ' ')"
  cp "$blocks/1" tests/Web.UnitTests/PageTest.cs
  cp "$blocks/3" tests/Web.UnitTests/OrdersPageTests.cs
  run test-guardian.sh green "$t" "FullyQualifiedName~OrdersPageTests"
  if ! check "$tfm: the tests of what the users see, on the Blazorise DataGrid: green twice" 0 '^GREEN: 4 tests pass, twice$'; then
    dump_markup "$work/$tfm-datagrid.html"
    markup "$work/$tfm-datagrid.html" "Blazorise DataGrid"
    tail -n 15 "$work/$tfm-datagrid.html.log" | sed 's/^/    /'
    return 0
  fi
  run test-guardian.sh coverage F1-net "$t" "$page"
  check "$tfm: coverlet measures the .razor page" 0 '^src/Web/Components/Pages/Orders\.razor lines [1-9][0-9]*/[0-9]+ '
  note "$tfm, the page on the DataGrid, with its tests: $(printf '%s\n' "$out" | grep '^src/Web/Components/Pages/Orders.razor')"
  folder=$("$SHELL_UNDER_TEST" "$scripts/test-guardian.sh" folder | sed -n 's/^FOLDER: //p')
  note "$tfm: coverlet reports for Orders.razor the methods $(razor_methods "$folder/results-F1-net" | tr "\n" " ")"
  run test-guardian.sh net F1-net "$page:OnInitialized" "$page:BuildRenderTree"
  check "$tfm: the net of the page with its tests: OK" 0 '^SAFETY NET: OK '
  note "$tfm, with its tests: $(printf '%s\n' "$out" | grep -E '^(NET|SAFETY NET):' | cut -c1-160 | tr '\n' ' ')"
  run test-lint.sh tests/Web.UnitTests/OrdersPageTests.cs tests/Web.UnitTests/PageTest.cs
  check "$tfm: test-lint on the tests of the page" 0 '^TEST LINT: OK'
  run test-guardian.sh tests-only
  check "$tfm: only the test project changed" 0 '^TESTS-ONLY: OK'
  run test-guardian.sh seal F1 tests/Web.UnitTests/OrdersPageTests.cs
  check "$tfm: the tests of the page sealed" 0 '^SEALED: 1 test files'
  commit "test: the safety net of the orders page"

  # ---- the coder, first step: the native components of the application, next to Blazorise ----
  run blazor-native.sh scaffold src/Web
  check "$tfm: scaffold: the native components written" 0 "^SCAFFOLD: src/Web/Components/Native \\(namespace Web\\.Components\\.Native, $tfm\\)\$"
  check "$tfm: scaffold: their @using" 0 '^IMPORTS: @using Web\.Components\.Native added to src/Web/Components/_Imports\.razor$'
  run build-test.sh --build-only src/Web/Web.csproj
  if ! check "$tfm: the native components build next to Blazorise (no name of theirs meets one of its)" 0 '^BUILD: OK'; then
    return 0
  fi
  commit "feat: the native components of the application"

  # ---- the coder: the page in native Razor (the native page of the skill) ----
  cp "$blocks/4" "$page"
  run test-guardian.sh sealed F1
  check "$tfm: the sealed tests, unchanged" 0 '^SEAL: OK'
  run test-guardian.sh green "$t" "FullyQualifiedName~OrdersPageTests"
  if ! check "$tfm: the same tests on the native page (NativeGrid): green twice" 0 '^GREEN: 4 tests pass, twice$'; then
    dump_markup "$work/$tfm-native.html"
    markup "$work/$tfm-native.html" "NativeGrid"
    tail -n 15 "$work/$tfm-native.html.log" | sed 's/^/    /'
    return 0
  fi
  run test-guardian.sh coverage F1-after "$t" "$page" src/Web/Components/Native/NativeGrid.razor
  note "$tfm, the native page, with the same tests: $(printf '%s\n' "$out" | grep -E '^src/Web/Components/(Pages/Orders|Native/NativeGrid)\.razor' | tr '\n' ' ')"
  run test-guardian.sh compare F1-before F1-after
  check "$tfm: no coverage lost (compare)" 0 '^COVERAGE: no file lost coverage$'
  run test-guardian.sh net F1-after "$page:OnInitialized" "$page:BuildRenderTree"
  check "$tfm: the net of the native page: kept" 0 '^SAFETY NET: OK '
  note "$tfm, the native page: $(printf '%s\n' "$out" | grep -E '^(NET|SAFETY NET):' | cut -c1-160 | tr '\n' ' ')"
  run test-guardian.sh sealed F1
  check "$tfm: sealed before the commit" 0 '^SEAL: OK'
  commit "refactor: the orders page in native Razor"

  # ---- the native components themselves, through a page that uses them all ----
  native_demo
  run test-guardian.sh green "$t" "FullyQualifiedName~NativeComponentsTests"
  if ! check "$tfm: the native components (grid, dialog, questions, toasts, field classes): green twice" 0 '^GREEN: 13 tests pass, twice$'; then
    # what the compiler said, when the page or its tests do not build
    dotnet build "$t" --nologo -v q 2>&1 | grep -E 'error [A-Z]+[0-9]+' | sed -E 's/ \[[^]]*\]$//' | sort -u | head -n 15 | sed 's/^/    /'
    return 0
  fi
  commit "test: the native components"
  run blazor-native.sh check
  check "$tfm: check before the last step: what is left, exit 1" 1 '^BLAZORISE: [0-9]+ place\(s\) left$'
  check "$tfm: check before the last step: the packages, the usings, the registration, the links" 1 '^LEFT: project: src/Web/Web\.csproj:[0-9]+:.*Blazorise\.DataGrid' 'LEFT: .*Components/Native/'

  # ---- the last step: Blazorise leaves ----
  sed -i '/Include="Blazorise\./d' src/Web/Web.csproj
  sed -i '/^using Blazorise/d; /AddBlazorise/d' src/Web/Program.cs
  sed -i '/@using Blazorise/d' src/Web/Components/_Imports.razor
  sed -i '/_content\/Blazorise/d' src/Web/Components/App.razor
  rm -f src/Web/Components/GridTexts.cs src/Web/Components/BlazoriseLanguage.razor
  sed -i '/^using Blazorise/d; /Blazorise/d; /IComponentActivator/,/^        }$/d' tests/Web.UnitTests/PageTest.cs
  sed -i '/^using Microsoft.AspNetCore.Components;$/d; /^using Microsoft.Extensions.DependencyInjection;$/d; /^using Microsoft.Extensions.DependencyInjection.Extensions;$/d' tests/Web.UnitTests/PageTest.cs
  left=$(git grep -n -i blazorise -- . ':!*.md' 2>/dev/null)
  [ -z "$left" ]
  verdict "$tfm: no Blazorise left in the code${left:+ ($(printf '%s' "$left" | head -n 3 | tr '\n' ' '))}" $?
  run blazor-native.sh check
  check "$tfm: check: GONE" 0 '^BLAZORISE: GONE ' '^LEFT: '
  run build-test.sh "$t"
  check "$tfm: without Blazorise, the build and every test green" 0 '^TESTS: OK' 'FAILED TESTS'
  run test-guardian.sh sealed F1
  check "$tfm: the tests of the page still as sealed" 0 '^SEAL: OK'
  commit "chore: remove Blazorise"
}

scenario net10.0
if dotnet --list-sdks | grep -q '^8\.'; then
  scenario net8.0
else
  note "no .NET 8 SDK here: the net8.0 story is not tried"
fi

echo "blazor-native-test ($SHELL_UNDER_TEST): $pass passed, $fail failed"
[ "$fail" -eq 0 ]
