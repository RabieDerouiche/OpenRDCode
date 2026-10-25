---
name: blazorise
description: Blazorise in a Blazor application - the language of the DataGrid and of its pager, its texts, the API of the installed version, and its replacement by native Razor (QuickGrid, EditForm, Bootstrap) page by page, each page under a safety net of bUnit tests of what its users see. Load before writing, fixing, reviewing, testing or removing code that uses Blazorise components.
compatibility: opencode
---
# Blazorise

Blazorise is paid: since 2023 a commercial license per front-end developer for any company (the free Community license is for eligible individual developers; `package-licenses.sh`), and without its product token its DataGrid shows 1 000 rows at most (a grid that stops at 1 000 rows is the license, not a bug). Never add a Blazorise package, never raise its version as a side effect: an upgrade, like the removal, is a ticket of its own.

## First: the version, and the API of that version (two reads, then decide)
- The version: `detect-project-type.sh` gives it ("Blazorise 2.2.2: the skill blazorise"), otherwise the PackageReference or `Directory.Packages.props`.
- The API of that version: `sh ~/.config/opencode/scripts/package-refs.sh --doc Blazorise.DataGrid` gives its XML documentation; grep tool on the member (`DataGridLocalizers.`, `.Localizers`, `.Page`, `.PagerOptions`). A member absent from it does not exist in this version: never invent one, never decompile, never search again in another way. There is no `DataGridLocalization` type and no `Culture` or `Language` parameter on `DataGrid`: the language comes from the localizer below.
- What 2.0 (February 2026, .NET 8, 9 and 10 only) renamed: the inputs `TextEdit`, `NumericEdit`, `DateEdit`, `TimeEdit`, `MemoEdit`, `ColorEdit`, `FileEdit` → `TextInput`, `NumericInput`, `DateInput`, `TimeInput`, `MemoInput`, `ColorInput`, `FileInput`, and their value parameters (`Text`, `Date`, `Time`, `Checked`, `SelectedValue`, `CheckedValue`, `Color`) → `Value` / `ValueChanged`; `Radio` only inside a `RadioGroup`; `MessageAlert`, `NotificationAlert`, `PageProgressAlert` → `MessageProvider`, `NotificationProvider`, `PageProgressProvider`; the DataGrid `CurrentPage` → `Page` (in the pager templates `context.CurrentPage` and `context.CurrentPageSize` → `context.Page` and `context.PageSize`), `GroupRowStyling` → `AggregateRowStyling`, `Navigable` → `NavigationMode`, `PopupFieldColumnSize` → `EditFieldColumnSize`, `SavedRowItem.Item` and `CancellableRowChange.Item` → `OldItem`, `DataGridPageChangedEventArgs` removed; `Centered`, `Scrollable` and `Size` of `ModalContent` → `Modal`; `BlazoriseOptions.LicenseKey` → `ProductToken`. Code is written for the version of the repository, never for another.

## The language of the DataGrid and of its pager
Its texts come from the Blazorise localizer: `ITextLocalizerService.SelectedCulture`, taken from the UI culture when the service is created (one per circuit, or per application in WebAssembly). The DataGrid of 2.x ships cs, da, de, en, es, fr, hr, is, it, nl, pl, pt, ro, ru, sk, tr, zh. In this order:

1. The texts of Blazorise in French, nothing else changed (the formats of dates and numbers stay as they are), for each user, in an interactive component that renders before the grid with its render mode (`MainLayout.razor` when the whole application is interactive, otherwise the page: a static layout renders in another scope than the circuit of the grid):
   ```razor
   @inject Blazorise.Localization.ITextLocalizerService LocalizationService
   @code {
       protected override void OnInitialized() => LocalizationService.ChangeLanguage("fr-FR", false);
   }
   ```
   `false` keeps the culture of the thread: with `true` (the default), Blazor Server changes it for every user of the server. When the whole application is French already (`UseRequestLocalization` with fr-FR on the server, `CultureInfo.DefaultThreadCurrentUICulture` in WebAssembly), the grid is French without this. Changing the culture of the application changes every date and number format: a decision of its own (« Décisions »), never a side effect. `<InvariantGlobalization>true</InvariantGlobalization>` leaves only the invariant culture: no language at all.
2. Texts to change or correct (the French of Blazorise says « items », « items par page », « {0} - {1} de {2} items », « Sauvegarder », « Meilleur que ou égal »): the `Localizers` parameter, ONE instance for the application, that every grid points to:
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
           FilterMethodGreaterThanOrEqualLocalizer = (name, args) => "Supérieur ou égal",
       };
   }
   ```
   Every grid takes it, as the orders page does (the page of the examples below; `Order`, `IOrderSource` are classes of the application):
   ```razor
   @page "/commandes"
   @inject IOrderSource Source

   <h1>Commandes</h1>
   <DataGrid TItem="Order" Data="@orders" ShowPager PageSize="5" Localizers="@GridTexts.French">
       <DataGridColumn TItem="Order" Field="@nameof(Order.Number)" Caption="Numéro" />
       <DataGridColumn TItem="Order" Field="@nameof(Order.Date)" Caption="Date" DisplayFormat="{0:dd/MM/yyyy}" />
       <DataGridColumn TItem="Order" Field="@nameof(Order.Total)" Caption="Total" DisplayFormat="{0:N2}" />
   </DataGrid>

   @code {
       private IReadOnlyList<Order> orders = Array.Empty<Order>();

       protected override void OnInitialized() => orders = Source.All();
   }
   ```
   A handler gets `name` (the English key) and `arguments` (the values to format) and replaces the text in every language: switch on `CultureInfo.CurrentUICulture` inside when the application has several. The pager: `FirstPageButtonLocalizer`, `PreviousPageButtonLocalizer`, `NextPageButtonLocalizer`, `LastPageButtonLocalizer`, `ItemsPerPageLocalizer`, `ItemsLocalizer`, `NumbersOfItemsLocalizer` (1.6 to 2.4); the buttons and the filters: `New…`, `Edit…`, `Delete…`, `Save…`, `Cancel…`, `FilterMethod…Localizer` (the XML documentation lists those of the version).
   Not this: `ITextLocalizer<DataGrid<TItem>>.AddLanguageResource` with the culture "fr" changes nothing (the first resource of a culture wins, and Blazorise ships "fr"), and that localizer is one per item type.
3. The markup of the pager (icons, layout): its templates `FirstPageButtonTemplate`, `PreviousPageButtonTemplate`, `NextPageButtonTemplate`, `LastPageButtonTemplate`, `PageButtonTemplate` (`context.PageNumber`), `ItemsPerPageTemplate`, `TotalItemsTemplate` and `TotalItemsShortTemplate` (`context.TotalItems`), `PageSelectorTemplate`, `PageSizesTemplate` (`context.PageSize`, `context.PageSizes`); `PagerOptions` (`ButtonSize`, `PaginationPosition`, `TotalItemsPosition`), `PagerPosition`, `PageSizes`.
- The proof: a bUnit test of the page that finds « Suivante » and the French formats (the tests below), when the test project has bUnit; otherwise a line of the checklist of the step.

## Replacing Blazorise with native Razor, page by page
Native Razor: the components of ASP.NET Core (`EditForm` and its `Input…` components, `QuickGrid`, `Virtualize`, `NavLink`), HTML with the Bootstrap classes the application already loads, and a few small components of the application where Blazorise gave a ready one (a pager, a modal, a toast). Free; QuickGrid is a package of Microsoft (MIT) of the version of the target framework.

How the pack runs it (`/go sans ticket : remplacer Blazorise par du Razor natif dans la page Commandes`, or a ticket):
- the analyst: the inventory below, then one step per page or family of components, each « (filet d'abord) » and « (s'appuyer sur le skill blazorise) », the leaves first (icons, buttons, layout), then forms, dialogs and messages, then grids; the last step removes the packages, the registrations and the links. A package the plan needs (QuickGrid) goes to « Décisions », the free option first (a native `<table>` and the pager below need none).
- the test-guardian, before each step (mission « filet »): the tests of what the users see on the page, green on Blazorise, then sealed; its net is measured on the page itself (`test-guardian.sh net <label> <page>.razor:BuildRenderTree <page>.razor:<a method of its @code>`). No bUnit in the unit test projects (`fortify.sh prereq --tests` says « COMPONENT TESTS: none »): the pilot asks the developer, then `test-guardian.sh setup --components` adds it.
- the coder: the page in native Razor; the sealed tests pass as they are; the test base class below is the only test file that changes, at the last step.

1. The inventory, before any change, three reads: `git grep -h -o -E '<[A-Z][A-Za-z0-9]*' -- '*.razor' | sort | uniq -c | sort -rn` (every component tag of the pages, with its count), `git ls-files '*.razor' | sed -E 's#.*/##; s#\.razor$##' | sort -u` (the components of the application, one per file), and `git grep -n -E 'INotificationService|IMessageService|IModalService|IToastService|IPageProgressService|ITextLocalizer|AddBlazorise|ProductToken|_content/Blazorise' -- '*.cs' '*.razor' '*.cshtml' '*.html'` (its services, registrations and links). The tags of the first that are neither the application's (the second) nor of ASP.NET Core (`EditForm`, `Input…`, `DataAnnotationsValidator`, `ValidationMessage`, `ValidationSummary`, `NavLink`, `PageTitle`, `HeadOutlet`, `HeadContent`, `Router`, `RouteView`, `Found`, `NotFound`, `AuthorizeView`, `Authorized`, `NotAuthorized`, `CascadingValue`, `CascadingAuthenticationState`, `DynamicComponent`, `ErrorBoundary`, `Virtualize`, `QuickGrid`, `PropertyColumn`, `TemplateColumn`, `Paginator`, `LayoutView`, `ChildContent`) are Blazorise, its templates (`DisplayTemplate`, `EmptyTemplate`…) included. The plan lists them per page.
2. The safety net of a step: bUnit tests of what the users see, written on the Blazorise version, kept as they are on the native one. They find what a user sees (the texts of the headers and of the cells through `thead th`, `tbody tr`, `td`, the text of a button), never a CSS class, an id or a component type of Blazorise (they leave with it); the culture of the users is fixed; `WaitForAssertion` waits for the rows (a grid renders them after its data). One base class registers what the pages need (the version of bUnit of the test project decides the API: `BunitContext` and `Render` from 2.0, `TestContext` and `RenderComponent` before):
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
   public abstract class PageTestContext : BunitContext
   {
       protected PageTestContext()
       {
           CultureInfo.CurrentCulture = CultureInfo.CurrentUICulture = CultureInfo.GetCultureInfo("fr-FR");
           JSInterop.Mode = JSRuntimeMode.Loose;
           Services.AddBlazorise().AddBootstrap5Providers().AddFontAwesomeIcons();
           // Blazorise registers its component activator as scoped: bUnit needs it transient
           var activator = Services.LastOrDefault(d => d.ServiceType == typeof(IComponentActivator));
           if (activator?.ImplementationType is { } type)
           {
               Services.Replace(ServiceDescriptor.Transient(typeof(IComponentActivator), type));
           }
       }
   }
   ```
   The tests of the page (its columns, its first page, its French formats, the next page, the sort), green on the DataGrid above and on its native version below:
   ```csharp
   using Bunit;
   using Microsoft.Extensions.DependencyInjection;
   using Web.Components.Pages;
   using Web.Data;
   using Xunit;

   namespace Web.UnitTests;

   // What the users see on the orders page: written before its grid is replaced, kept as they are after
   public class OrdersPageTests : PageTestContext
   {
       public OrdersPageTests()
       {
           var orders = Enumerable.Range(1, 12)
               .Select(i => new Order($"CMD-{i:00}", new DateTime(2026, 1, i), 10.5m * i))
               .ToList();
           Services.AddSingleton<IOrderSource>(new FixedOrders(orders));
       }

       [Fact]
       public void Orders_FirstPage_ShowsTheThreeColumnsAndFiveOrders()
       {
           var cut = Render<Orders>();

           cut.WaitForAssertion(() =>
           {
               Assert.Equal(new[] { "Numéro", "Date", "Total" }, Headers(cut));
               Assert.Equal(new[] { "CMD-01", "CMD-02", "CMD-03", "CMD-04", "CMD-05" }, Numbers(cut));
           });
       }

       [Fact]
       public void Orders_FirstRow_ShowsItsDateAndTotalInFrench()
       {
           var cut = Render<Orders>();

           cut.WaitForAssertion(() => Assert.Equal(new[] { "CMD-01", "01/01/2026", "10,50" }, Cells(cut, 0)));
       }

       [Fact]
       public void Orders_NextPage_ShowsTheNextFiveOrders()
       {
           var cut = Render<Orders>();
           cut.WaitForAssertion(() => Assert.Equal(5, Numbers(cut).Length));

           cut.FindAll("a, button").First(e => e.TextContent.Trim() == "Suivante").Click();

           cut.WaitForAssertion(() =>
               Assert.Equal(new[] { "CMD-06", "CMD-07", "CMD-08", "CMD-09", "CMD-10" }, Numbers(cut)));
       }

       [Fact]
       public void Orders_SortedTwiceByNumber_ShowsTheLastOrderFirst()
       {
           var cut = Render<Orders>();
           cut.WaitForAssertion(() => Assert.Equal(5, Numbers(cut).Length));

           SortBy(cut, "Numéro");
           SortBy(cut, "Numéro");

           cut.WaitForAssertion(() => Assert.Equal("CMD-12", Numbers(cut)[0]));
       }

       private static string[] Headers(IRenderedComponent<Orders> cut) =>
           cut.FindAll("thead th").Select(th => th.TextContent.Trim()).Where(text => text.Length > 0).ToArray();

       private static string[] Numbers(IRenderedComponent<Orders> cut) =>
           cut.FindAll("tbody tr").Select(tr => tr.QuerySelector("td")?.TextContent.Trim() ?? "").ToArray();

       private static string[] Cells(IRenderedComponent<Orders> cut, int row) =>
           cut.FindAll("tbody tr")[row].QuerySelectorAll("td").Select(td => td.TextContent.Trim()).ToArray();

       // the header of a column: its button when it has one (QuickGrid), otherwise the cell itself (the DataGrid)
       private static void SortBy(IRenderedComponent<Orders> cut, string title)
       {
           var header = cut.FindAll("thead th").First(th => th.TextContent.Trim() == title);
           (header.QuerySelector("button") ?? header).Click();
       }

       private sealed class FixedOrders(IReadOnlyList<Order> orders) : IOrderSource
       {
           public IReadOnlyList<Order> All() => orders;
       }
   }
   ```
   What the page keeps, each in a test or a line of the checklist of the step: its columns and their order, the formats (culture), the default sort, the page size, the text of an empty list, the events (a click on a row), the authorizations.
3. The equivalents (Bootstrap markup, the CSS the application loads already):

| Blazorise | Native |
|---|---|
| `DataGrid`, `DataGridColumn Field Caption DisplayFormat`, `ShowPager PageSize` | `QuickGrid Items` + `PropertyColumn Property Title Format Sortable="true"` + `PaginationState { ItemsPerPage = <its page size> }` and the pager below; or a `<table class="table">` with Skip/Take (no package) |
| `ReadData` (data paged by the server) | `ItemsProvider` of QuickGrid (`GridItemsProviderResult.From(items, totalItemCount)`) |
| `DataGridCommandColumn`, edit in the row or in a popup | `TemplateColumn` with buttons; the edit in an `EditForm` (a row, or the modal of the application) |
| `Filterable` (the filter row) | `ColumnOptions` of a `PropertyColumn` with an `<input>`, and a `Where` on `Items` |
| `SelectionMode`, `SelectedRow` | a `TemplateColumn` with a checkbox, and a `HashSet` of the selected items |
| `Groupable`, `Aggregates` | computed in C#: a summary row of a native `<table>` |
| `TextInput`, `NumericInput`, `DateInput`, `MemoInput`, `FileInput`, `Select`, `Check`, `Switch`, `RadioGroup`/`Radio` | `InputText`, `InputNumber`, `InputDate`, `InputTextArea`, `InputFile`, `InputSelect`, `InputCheckbox` (`form-check`; a switch: `form-check form-switch` and `role="switch"`), `InputRadioGroup`/`InputRadio`, in an `EditForm` |
| `Validations`, `Validation`, `ValidationRule` | `DataAnnotationsValidator`, `ValidationMessage`, the attributes of the model; the Bootstrap classes below |
| `Field`, `FieldLabel`, `FieldHelp` | `<div class="mb-3">`, `<label class="form-label">`, `<div class="form-text">` |
| `Button Color="Color.Primary"`, `Badge`, `Alert`, `Card`, `Row`/`Column`, `Progress`, `Spinner` | `<button type="button" class="btn btn-primary">`, `badge text-bg-…`, `alert alert-…`, `card`, `row`/`col-md-6`, `progress`, `spinner-border` |
| `Modal`, `IModalService`, `IMessageService` (confirm) | a component of the application: Bootstrap modal markup shown with `@if` (or `<dialog>`), and a confirmation component |
| `INotificationService`, `IToastService`, `Snackbar` | a scoped toast service of the application and its component |
| `Tabs`/`Tab`/`TabPanel`, `Dropdown`, `Tooltip`, `Bar` (navbar) | `nav nav-tabs` with the active tab in a field; `dropdown-menu` with `show` toggled in C#; the `title` attribute; `navbar` and `NavLink` (their JavaScript replaced by state in C#) |
| `Icon Name="IconName.Edit"` | the CSS icons the application loads (`<i class="bi bi-pencil" aria-hidden="true">`) |
| `Autocomplete` | `<input list="…">` and a `<datalist>`, or a component of the application |
| `Blazorise.Charts`, `RichTextEdit` | Chart.js or the editor through a small JS module: a step of its own |

4. What changes without a compiler error, checked in each step:
   - Typing: a Blazorise input changes its value on each key press (`Immediate`, true unless `BlazoriseOptions` says otherwise; `Debounce` 300 ms when set); `InputText` changes it when the field loses the focus. A search that filters while typing: `<input class="form-control" @bind="search" @bind:event="oninput" @bind:after="FilterAsync" />`.
   - Sort: every DataGrid column sorts on a click (`Sortable` is true by default); a `PropertyColumn` only with `Sortable="true"`; the default sort: `IsDefaultSortColumn` and `InitialSortDirection` on the column.
   - Page size: `ItemsPerPage` of `PaginationState` is 10 by default: give the page size of the grid.
   - Validation: Blazorise shows Bootstrap's `is-invalid` and `invalid-feedback`; `EditForm` writes `invalid` and `validation-message`. Its Bootstrap look, with `editContext.SetFieldCssClassProvider(new BootstrapFieldCssClassProvider())` and `.validation-message` styled as `.invalid-feedback` in the CSS of the application:
     ```csharp
     using Microsoft.AspNetCore.Components.Forms;

     // The Bootstrap classes of a field: is-invalid once its validation failed, is-valid once the user changed it
     public sealed class BootstrapFieldCssClassProvider : FieldCssClassProvider
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
     ```
   - Dates and numbers: `DateInput` and `DatePicker` show the format of the application; `InputDate` is the date picker of the browser, in the language of the browser (the value is the same); `NumericInput` formats while typing, `InputNumber` does not.
   - A click on a row (`RowClicked`, `SelectedRowChanged`): QuickGrid has no row event (.NET 10): a button or a link in a `TemplateColumn`, or a native `<table>` whose `<tr>` has `@onclick` and a keyboard equivalent.
   - An empty list: QuickGrid has no template for it (`EmptyTemplate` of the DataGrid): an `@if` with the same text before the grid.
   - The links of `_content/Blazorise…` (CSS, icons of `Blazorise.Icons.FontAwesome`): the icons and styles the pages keep come from the application's own `wwwroot` (or its CDN link) before the package leaves.
5. QuickGrid writes « Page 1 of 3 » and « Go to next page » in English with its `Paginator` (only `SummaryTemplate` changes): its French pager is a component of the application over `PaginationState`, with the words of the DataGrid it replaces (the users and the tests find the same buttons):
   ```razor
   @* FrenchPager.razor: the pager of a QuickGrid, with the words of the DataGrid it replaces *@
   @using Microsoft.AspNetCore.Components.QuickGrid
   @implements IDisposable

   @if (State.TotalItemCount is int total && total > 0)
   {
       <nav class="d-flex flex-wrap align-items-center gap-2" aria-label="Pagination">
           <button type="button" class="btn btn-sm btn-outline-secondary" disabled="@(!CanGoBack)" @onclick="() => GoToAsync(0)">Première</button>
           <button type="button" class="btn btn-sm btn-outline-secondary" disabled="@(!CanGoBack)" @onclick="() => GoToAsync(State.CurrentPageIndex - 1)">Précédente</button>
           <span>Page @(State.CurrentPageIndex + 1) sur @(LastIndex + 1) · @total @(total > 1 ? "éléments" : "élément")</span>
           <button type="button" class="btn btn-sm btn-outline-secondary" disabled="@(!CanGoForward)" @onclick="() => GoToAsync(State.CurrentPageIndex + 1)">Suivante</button>
           <button type="button" class="btn btn-sm btn-outline-secondary" disabled="@(!CanGoForward)" @onclick="() => GoToAsync(LastIndex)">Dernière</button>
       </nav>
   }

   @code {
       [Parameter, EditorRequired] public PaginationState State { get; set; } = default!;

       private int LastIndex => State.LastPageIndex ?? 0;
       private bool CanGoBack => State.CurrentPageIndex > 0;
       private bool CanGoForward => State.CurrentPageIndex < LastIndex;

       protected override void OnInitialized() => State.TotalItemCountChanged += OnTotalItemCountChanged;

       private void OnTotalItemCountChanged(object? sender, int? count) => _ = InvokeAsync(StateHasChanged);

       private Task GoToAsync(int pageIndex) => State.SetCurrentPageIndexAsync(pageIndex);

       public void Dispose() => State.TotalItemCountChanged -= OnTotalItemCountChanged;
   }
   ```
   The orders page of the DataGrid above, in native Razor (its sealed tests pass as they are):
   ```razor
   @page "/commandes"
   @using Microsoft.AspNetCore.Components.QuickGrid
   @inject IOrderSource Source

   <h1>Commandes</h1>
   <QuickGrid Items="@orders" Pagination="@pagination" Class="table">
       <PropertyColumn Property="@(o => o.Number)" Title="Numéro" Sortable="true" />
       <PropertyColumn Property="@(o => o.Date)" Title="Date" Format="dd/MM/yyyy" Sortable="true" />
       <PropertyColumn Property="@(o => o.Total)" Title="Total" Format="N2" Sortable="true" />
   </QuickGrid>
   <FrenchPager State="@pagination" />

   @code {
       private IQueryable<Order> orders = Enumerable.Empty<Order>().AsQueryable();
       private readonly PaginationState pagination = new() { ItemsPerPage = 5 };

       protected override void OnInitialized() => orders = Source.All().AsQueryable();
   }
   ```
   Sorting and paging need an interactive render mode, as the DataGrid did. Data paged by the server: `ItemsProvider` instead of `Items` (the request gives `StartIndex`, `Count` and the sort).
6. A package is the developer's decision, never the coder's: QuickGrid (`Microsoft.AspNetCore.Components.QuickGrid`, Microsoft, MIT, its major version is the one of the target framework: 8.0.x for net8.0, 10.0.x for net10.0); bUnit for the tests, through `test-guardian.sh setup --components` once the developer agreed. The analyst lists QuickGrid in « Décisions », the free option first; a step that needs it before it is there is « BLOQUÉ ».
7. The last step: no `Blazorise.*` PackageReference or PackageVersion left; in `Program.cs` no `AddBlazorise(…)`, `AddBootstrap5Providers()`, `AddFontAwesomeIcons()` (or the providers of the repository) nor `ProductToken` (a license token: never printed, never committed; the developer removes it from the configuration); in `_Imports.razor` no `@using Blazorise…`; in `App.razor`, `_Host.cshtml` or `index.html` no `_content/Blazorise…` link and no `ThemeProvider`, `MessageProvider`, `NotificationProvider`, `ModalProvider`, `ToastProvider`; `GridTexts` and the language component above removed; the test base class keeps its culture and its JavaScript, without Blazorise. Then `git grep -n -i blazorise` finds only the history of the documentation, the build and every test pass.
