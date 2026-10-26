---
name: blazorise
description: Blazorise in a Blazor application - its replacement by 100 % native Razor (no package - native components of the application written by blazor-native.sh, page by page under bUnit tests of what its users see, the inventory and the check of what is left done by script), and, while it is still there, the API of the installed version and the language of its DataGrid. Load before writing, fixing, reviewing, testing or removing code that uses Blazorise components.
compatibility: opencode
---
# Blazorise

Blazorise is paid: a commercial license per front-end developer for any company (the free Community license is for eligible individual developers; `package-licenses.sh`), and without its product token its DataGrid shows 1 000 rows at most (a grid that stops at 1 000 rows is the license, not a bug). Never add a Blazorise package, never raise its version as a side effect: an upgrade, like the removal, is a ticket of its own.

## Replacing Blazorise by native Razor, 100 % native
Native: the components of ASP.NET Core (`EditForm` and its `Input…`, `NavLink`, `Virtualize`), HTML with the Bootstrap classes the application already loads, and the native components of the application that `blazor-native.sh scaffold` writes once, in its own code: `NativeGrid` with `NativeColumn` and `NativeTemplateColumn` (a table: a click on a title sorts, the pages and a pager with the words of the DataGrid, « Première », « Précédente », « Suivante », « Dernière », the text of an empty list, a click on a row and the selected row, the data of a server), `NativeModal`, `NativeDialogService` with `NativeDialogHost` (the questions and messages of `IMessageService`), `NativeToastService` with `NativeToastHost`, `NativeFieldCssClassProvider`. No package at all: not even QuickGrid. They are all named `Native…`: none meets a name of Blazorise while both are in the application.

How the pack runs it (`/go sans ticket : remplacer Blazorise par du Razor natif dans <the pages, or toute l'application>`, or a ticket):
- the analyst: `sh ~/.config/opencode/scripts/blazor-native.sh inventory` (one call; never the tags counted by hand). Its PAGE lines are the order of the plan: one step per page (« step <n> »), each ending « (filet d'abord) (s'appuyer sur le skill blazorise) »; before them, one step « écrire les composants natifs de l'application (blazor-native.sh scaffold <the web project>) », without a net (it only adds code nothing calls yet); after them, one step that removes the packages, the registrations, the usings, the links and the license keys. Its UNKNOWN TAG lines go to « Décisions » (a tag to check), its LICENSE KEY lines to « Points d'attention » (the developer removes the token from the configuration and the secret stores).
- the test-guardian, before each page (mission « filet »): the bUnit tests of what its users see, on the Blazorise version, green twice, sealed (below).
- the coder: the step of the components runs `sh ~/.config/opencode/scripts/blazor-native.sh scaffold <the web project>` (it writes them and their `@using`; it never writes over a file), then registers what the pages will need, when the inventory lists `IMessageService`, `INotificationService` or `IToastService`: `builder.Services.AddScoped<NativeDialogService>();`, `builder.Services.AddScoped<NativeToastService>();` in `Program.cs`, `<NativeDialogHost />`, `<NativeToastHost />` in the layout (in the page itself when only the page is interactive: a question without a host stops with an exception that says so). Each page step rewrites the page with the equivalents below, and is done when the sealed tests pass as they are, twice. The last step ends when `sh ~/.config/opencode/scripts/blazor-native.sh check` says « BLAZORISE: GONE », with the build and every test green.
- the checker: `sh ~/.config/opencode/scripts/blazor-native.sh check` on the last step; a LEFT line is a « majeur » point.

### The safety net of a page: tests of what its users see
Written on the Blazorise version, kept as they are on the native one. They find what a user sees: the texts of the headers and of the cells (`thead th`, `tbody tr`, `td`), the text of a button, never a CSS class, an id or a component type of Blazorise (they leave with it); the culture of the users is fixed; `WaitForAssertion` waits for the rows (a grid renders them after its data); each test disposes its context with `await using` (some services of a page are disposed asynchronously only: « type only implements IAsyncDisposable » otherwise). No bUnit in the unit test projects (`fortify.sh prereq --tests` says « COMPONENT TESTS: none »): the pilot asks the developer, then `test-guardian.sh setup --components` adds it. The version of bUnit of the test project decides its API: `BunitContext` and `Render` from 2.0, `TestContext` and `RenderComponent` before.
One helper builds the context of the pages; the services of Blazorise go with its last step (the only test file that changes then):
```csharp
using System.Globalization;
using Blazorise;
using Blazorise.Bootstrap5;
using Blazorise.Icons.FontAwesome;
using Bunit;
using Microsoft.AspNetCore.Components;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;

namespace Web.UnitTests;

// What every page test needs: the culture of the users, the JavaScript of the browser answered by bUnit, and the
// services of the component library the pages still use (they leave with it, at the last step of its replacement)
public static class PageTest
{
    public static BunitContext Context()
    {
        CultureInfo.CurrentCulture = CultureInfo.CurrentUICulture = CultureInfo.GetCultureInfo("fr-FR");
        var ctx = new BunitContext();
        ctx.JSInterop.Mode = JSRuntimeMode.Loose;
        ctx.Services.AddBlazorise().AddBootstrap5Providers().AddFontAwesomeIcons();
        // Blazorise registers its component activator as scoped: bUnit needs it transient
        var activator = ctx.Services.LastOrDefault(d => d.ServiceType == typeof(IComponentActivator));
        if (activator?.ImplementationType is { } type)
        {
            ctx.Services.Replace(ServiceDescriptor.Transient(typeof(IComponentActivator), type));
        }

        return ctx;
    }
}
```
The page of the examples (`Order`, `IOrderSource` are classes of the application), on the DataGrid:
```razor
@page "/commandes"
@inject IOrderSource Source

<h1>Commandes</h1>
<DataGrid TItem="Order" Data="@orders" ShowPager PageSize="5">
    <DataGridColumn TItem="Order" Field="@nameof(Order.Number)" Caption="Numéro" />
    <DataGridColumn TItem="Order" Field="@nameof(Order.Date)" Caption="Date" DisplayFormat="{0:dd/MM/yyyy}" />
    <DataGridColumn TItem="Order" Field="@nameof(Order.Total)" Caption="Total" DisplayFormat="{0:N2}" />
</DataGrid>

@code {
    private IReadOnlyList<Order> orders = Array.Empty<Order>();

    protected override void OnInitialized() => orders = Source.All();
}
```
Its tests (its columns, its first page, its French formats, the next page, the sort), green on the DataGrid above and on its native version below:
```csharp
using Bunit;
using Microsoft.Extensions.DependencyInjection;
using Web.Components.Pages;
using Web.Data;
using Xunit;

namespace Web.UnitTests;

// What the users see on the orders page: written before its grid is replaced, kept as they are after
public class OrdersPageTests
{
    private static readonly IReadOnlyList<Order> TwelveOrders = Enumerable.Range(1, 12)
        .Select(i => new Order($"CMD-{i:00}", new DateTime(2026, 1, i), 10.5m * i))
        .ToList();

    [Fact]
    public async Task Orders_FirstPage_ShowsTheThreeColumnsAndFiveOrders()
    {
        await using var ctx = Context();
        var cut = ctx.Render<Orders>();

        cut.WaitForAssertion(() =>
        {
            Assert.Equal(new[] { "Numéro", "Date", "Total" }, Headers(cut));
            Assert.Equal(new[] { "CMD-01", "CMD-02", "CMD-03", "CMD-04", "CMD-05" }, Numbers(cut));
        });
    }

    [Fact]
    public async Task Orders_FirstRow_ShowsItsDateAndTotalInFrench()
    {
        await using var ctx = Context();
        var cut = ctx.Render<Orders>();

        cut.WaitForAssertion(() => Assert.Equal(new[] { "CMD-01", "01/01/2026", "10,50" }, Cells(cut, 0)));
    }

    [Fact]
    public async Task Orders_NextPage_ShowsTheNextFiveOrders()
    {
        await using var ctx = Context();
        var cut = ctx.Render<Orders>();
        cut.WaitForAssertion(() => Assert.Equal(5, Numbers(cut).Length));

        await cut.FindAll("a, button").First(e => e.TextContent.Trim() == "Suivante").ClickAsync();

        cut.WaitForAssertion(() =>
            Assert.Equal(new[] { "CMD-06", "CMD-07", "CMD-08", "CMD-09", "CMD-10" }, Numbers(cut)));
    }

    [Fact]
    public async Task Orders_SortedTwiceByNumber_ShowsTheLastOrderFirst()
    {
        await using var ctx = Context();
        var cut = ctx.Render<Orders>();
        cut.WaitForAssertion(() => Assert.Equal(5, Numbers(cut).Length));

        await SortByAsync(cut, "Numéro");
        await SortByAsync(cut, "Numéro");

        cut.WaitForAssertion(() => Assert.Equal("CMD-12", Numbers(cut)[0]));
    }

    private static BunitContext Context()
    {
        var ctx = PageTest.Context();
        ctx.Services.AddSingleton<IOrderSource>(new FixedOrders(TwelveOrders));
        return ctx;
    }

    private static string[] Headers(IRenderedComponent<Orders> cut) =>
        cut.FindAll("thead th").Select(th => th.TextContent.Trim()).Where(text => text.Length > 0).ToArray();

    private static string[] Numbers(IRenderedComponent<Orders> cut) =>
        cut.FindAll("tbody tr").Select(tr => tr.QuerySelector("td")?.TextContent.Trim() ?? "").ToArray();

    private static string[] Cells(IRenderedComponent<Orders> cut, int row) =>
        cut.FindAll("tbody tr")[row].QuerySelectorAll("td").Select(td => td.TextContent.Trim()).ToArray();

    // the header of a column: its button when it has one (NativeGrid), otherwise the cell itself (the DataGrid)
    private static Task SortByAsync(IRenderedComponent<Orders> cut, string title)
    {
        var header = cut.FindAll("thead th").First(th => th.TextContent.Trim() == title);
        return (header.QuerySelector("button") ?? header).ClickAsync();
    }

    private sealed class FixedOrders(IReadOnlyList<Order> orders) : IOrderSource
    {
        public IReadOnlyList<Order> All() => orders;
    }
}
```
What a page keeps, each in a test or a line of the checklist of its step: its columns and their order, the formats (culture), the default sort, the page size, the text of an empty list, the events (a click on a row), the authorizations. A page with a question or a message: its tests register `NativeDialogService` and `NativeToastService` too (`ctx.Services.AddSingleton<NativeDialogService>()`), render `NativeDialogHost` (`var dialogs = ctx.Render<NativeDialogHost>();`) before the page, click the button of the page without awaiting it (`var deleting = button.ClickAsync();`: it waits for the answer), click « Confirmer » in `dialogs`, then `await deleting`.

### The page in native Razor
The same page with `NativeGrid` (its sealed tests pass as they are). Its columns take the type of the grid (never `TItem` on a column):
```razor
@page "/commandes"
@inject IOrderSource Source

<h1>Commandes</h1>
<NativeGrid Items="@orders" ShowPager PageSize="5">
    <NativeColumn Field="@(o => o.Number)" Title="Numéro" />
    <NativeColumn Field="@(o => o.Date)" Title="Date" Format="dd/MM/yyyy" />
    <NativeColumn Field="@(o => o.Total)" Title="Total" Format="N2" />
</NativeGrid>

@code {
    private IReadOnlyList<Order> orders = Array.Empty<Order>();

    protected override void OnInitialized() => orders = Source.All();
}
```
The equivalents (the EQUIVALENT lines of the inventory give the one of each tag used):

| Blazorise | Native |
|---|---|
| `DataGrid Data ShowPager PageSize`, `EmptyTemplate`, `RowClicked`, `@bind-SelectedRow`, `RowStyling` | `NativeGrid Items ShowPager PageSize EmptyText RowClicked @bind-SelectedItem RowClass` |
| `DataGridColumn Field Caption DisplayFormat Sortable`, `IsDefaultSortColumn`, `InitialSortDirection`, `Displayable` | `NativeColumn Field="@(o => o.X)" Title Format Sortable` (`{0:N2}` works as is), `IsDefaultSort`, `Descending`; a column shown or not: `@if (…) { <NativeColumn … /> }` |
| `DataGridCommandColumn`, `DisplayTemplate`, edit in a row or a popup | `NativeTemplateColumn Title` with its buttons (`context` is the row; `SortBy="@(o => o.Total)"` to sort it; in a clickable row, a button has `@onclick:stopPropagation="true"`); the edit in an `EditForm` inside `NativeModal` |
| `ReadData` (data paged by the server) | `<NativeGrid TItem="Order" ItemsProvider="@LoadAsync">`: `ValueTask<NativeGridResult<Order>> LoadAsync(NativeGridRequest r)` with `r.StartIndex`, `r.Count`, `r.SortBy` (the member of the column: `Number`, `Customer.Name`), `r.Descending`, `r.CancellationToken`; after a change of the data, `await grid.RefreshAsync()` (`@ref="grid"`) |
| `Filterable` (the filter row), `SelectionMode`, `Groupable`, `Aggregates` | an `<input @bind="filter" @bind:event="oninput">` and a `Where` on `Items`; a `NativeTemplateColumn` with a checkbox and a `HashSet`; computed in C# (a summary row under the grid) |
| `TextInput`, `NumericInput`, `DateInput`, `MemoInput`, `FileInput`, `Select`, `Check`, `Switch`, `RadioGroup`/`Radio` | `InputText`, `InputNumber`, `InputDate`, `InputTextArea`, `InputFile`, `InputSelect`, `InputCheckbox` (`form-check`; a switch: `form-check form-switch`, `role="switch"`), `InputRadioGroup`/`InputRadio`, in an `EditForm` |
| `Validations`, `Validation`, `Field`, `FieldLabel`, `FieldHelp` | `DataAnnotationsValidator`, `ValidationMessage`, `editContext.SetFieldCssClassProvider(new NativeFieldCssClassProvider())`; `<div class="mb-3">`, `<label class="form-label">`, `<div class="form-text">` |
| `Modal` (`modalRef.Show()`), `ModalHeader`, `ModalBody`, `ModalFooter`; `IModalService.Show<T>()` | `<NativeModal @bind-Visible="editing" Title="…">…<Footer>…</Footer></NativeModal>` (or `@ref` and `Show()`, `Hide()`); the component of `Show<T>` inside it |
| `IMessageService.Confirm(...)`; `.Info`, `.Success`, `.Warning`, `.Error` | `if (await Dialogs.ConfirmAsync("Supprimer la commande ?"))` (`@inject NativeDialogService Dialogs`); `await Dialogs.AlertAsync("…")` |
| `INotificationService.Success(...)`, `IToastService`, `Snackbar` | `await Toasts.Success("Commande enregistrée")` (`@inject NativeToastService Toasts`; Info, Warning, Error alike) |
| `Button Color="Color.Primary"`, `Badge`, `Alert`, `Card`, `Row`/`Column`, `Progress`, `Spinner`, `Bar` | `<button type="button" class="btn btn-primary">`, `badge text-bg-…`, `alert alert-…`, `card`, `row`/`col-md-6`, `progress`, `spinner-border`, `navbar` and `NavLink` |
| `Tabs`/`Tab`/`TabPanel`, `Dropdown`, `Tooltip` | `nav nav-tabs` with the active tab in a field; `dropdown-menu` with `show` toggled in C#; the `title` attribute |
| `Icon Name="IconName.Edit"` | `<i class="…" aria-hidden="true"></i>` with the icon CSS the application loads from its own `wwwroot` or CDN link (never `_content/Blazorise.Icons…`, which leaves) |
| `Autocomplete` | `<input list="…">` and a `<datalist>` |
| `Blazorise.Charts`, `RichTextEdit` | a step of its own: the JS library through a small module of the application |

What changes without a compiler error, checked in each step:
- Typing: a Blazorise input changes its value on each key (`Immediate`); `InputText` when the field loses the focus. A search that filters while typing: `<input class="form-control" @bind="search" @bind:event="oninput" />`.
- Pages: `NativeGrid` pages only with `ShowPager` (10 rows by default, as the DataGrid); the first test of the page (its first page) shows how many rows Blazorise showed.
- Dates and numbers: `InputDate` is the date picker of the browser, in its language (the value is the same); `InputNumber` does not format while typing.
- Interactivity: sorting, pages and clicks need an interactive render mode, as the DataGrid did.

The last step: no `Blazorise.*` PackageReference or PackageVersion left; in `Program.cs` no `AddBlazorise(…)` and its providers, nor `ProductToken` (a license token: never printed, never committed; the developer removes it from the configuration and the secret stores); in `_Imports.razor` no `@using Blazorise…`; in `App.razor`, `_Host.cshtml` or `index.html` no `_content/Blazorise…` link and no `ThemeProvider`, `MessageProvider`, `NotificationProvider`, `ModalProvider`, `ToastProvider`; the language component and `DataGridLocalizers` below removed; the test helper keeps its culture and its JavaScript, without Blazorise. Then `blazor-native.sh check` says « BLAZORISE: GONE » (the Markdown documentation is not looked at), the build and every test pass.

## While Blazorise is there: the API of its version
- The version: `detect-project-type.sh` gives it, otherwise the PackageReference or `Directory.Packages.props`; its API: `sh ~/.config/opencode/scripts/package-refs.sh --doc Blazorise.DataGrid` gives its XML documentation (grep tool on the member). A member absent from it does not exist in this version: never invent one, never decompile. There is no `DataGridLocalization` type and no `Culture` or `Language` parameter on `DataGrid`.
- What 2.0 (February 2026) renamed: `TextEdit`, `NumericEdit`, `DateEdit`, `TimeEdit`, `MemoEdit`, `ColorEdit`, `FileEdit` → `TextInput`, `NumericInput`, `DateInput`, `TimeInput`, `MemoInput`, `ColorInput`, `FileInput`, their value parameters → `Value` / `ValueChanged`; `MessageAlert`, `NotificationAlert`, `PageProgressAlert` → `MessageProvider`, `NotificationProvider`, `PageProgressProvider`; the DataGrid `CurrentPage` → `Page` (`context.Page`, `context.PageSize` in its pager templates), `Navigable` → `NavigationMode`, `SavedRowItem.Item` → `OldItem`; `BlazoriseOptions.LicenseKey` → `ProductToken`. Code is written for the version of the repository, never for another.

## While Blazorise is there: the language of its DataGrid
Its texts come from its localizer, from the UI culture of the circuit. In French for each user, nothing else changed (formats of dates and numbers kept), in an interactive component rendered before the grid with its render mode (`MainLayout.razor` when the whole application is interactive):
```razor
@inject Blazorise.Localization.ITextLocalizerService LocalizationService
@code {
    protected override void OnInitialized() => LocalizationService.ChangeLanguage("fr-FR", false);
}
```
`false` keeps the culture of the thread (with `true`, Blazor Server changes it for every user of the server). Texts to correct (« items », « Sauvegarder »): ONE instance of `DataGridLocalizers` that every grid takes (`Localizers="@GridTexts.French"`):
```csharp
using System.Globalization;
using Blazorise.DataGrid;

// the texts of every DataGrid of the application
public static class GridTexts
{
    public static readonly DataGridLocalizers French = new()
    {
        FirstPageButtonLocalizer = (name, args) => "Première",
        PreviousPageButtonLocalizer = (name, args) => "Précédente",
        NextPageButtonLocalizer = (name, args) => "Suivante",
        LastPageButtonLocalizer = (name, args) => "Dernière",
        ItemsPerPageLocalizer = (name, args) => "éléments par page",
        ItemsLocalizer = (name, args) => "éléments",
        // "{0} - {1} of {2} items": the first item, the last item, the total
        NumbersOfItemsLocalizer = (name, args) => string.Format(CultureInfo.CurrentCulture, "{0} - {1} sur {2} éléments", args),
        SaveButtonLocalizer = (name, args) => "Enregistrer",
    };
}
```
Not this: `ITextLocalizer<DataGrid<TItem>>.AddLanguageResource` with "fr" changes nothing (Blazorise ships "fr" first). The proof: a bUnit test of the page that finds « Suivante » and the French formats.
