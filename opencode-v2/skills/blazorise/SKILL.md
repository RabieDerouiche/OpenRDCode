---
name: blazorise
description: Blazorise in a Blazor application - the language of the DataGrid and of its pager, its texts, the API of the installed version, and its replacement by native Razor (QuickGrid, EditForm, Bootstrap) step by step. Load before writing, fixing, reviewing or removing code that uses Blazorise components.
compatibility: opencode
---
# Blazorise

Blazorise is paid: a license per front-end developer (`package-licenses.sh`). Never add a Blazorise package, never raise its version as a side effect: an upgrade, like the removal, is a ticket of its own.

## First: the version, and the API of that version (two reads, then decide)
- The version: `detect-project-type.sh` gives it ("Blazorise 2.2.2: the skill blazorise"), otherwise the PackageReference or `Directory.Packages.props`.
- The API of that version: `sh ~/.config/opencode/scripts/package-refs.sh --doc Blazorise.DataGrid` gives its XML documentation; grep tool on the member (`DataGridLocalizers.`, `.Localizers`, `.Page`, `.PagerOptions`). A member absent from it does not exist in this version: never invent one, never decompile, never search again in another way. There is no `DataGridLocalization` type and no `Culture` or `Language` parameter on `DataGrid`: the language comes from the localizer below.
- What 2.0 (February 2026) renamed: `CurrentPage` → `Page` (the parameter of the DataGrid; in the pager templates `context.CurrentPage` and `context.CurrentPageSize` → `context.Page` and `context.PageSize`), `GroupRowStyling` → `AggregateRowStyling`, `Navigable` → `NavigationMode`, `PopupFieldColumnSize` → `EditFieldColumnSize`, `SavedRowItem.Item` and `CancellableRowChange.Item` → `OldItem`; `TextEdit`, `DateEdit`, `FileEdit` → `TextInput`, `DateInput`, `FileInput`; `DataGridPageChangedEventArgs` removed. Code is written for the version of the repository, never for another.

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
   ```razor
   <DataGrid TItem="Order" Data="@orders" ShowPager ShowPageSizes Localizers="@GridTexts.French">
   ```
   A handler gets `name` (the English key) and `arguments` (the values to format) and replaces the text in every language: switch on `CultureInfo.CurrentUICulture` inside when the application has several. The pager: `FirstPageButtonLocalizer`, `PreviousPageButtonLocalizer`, `NextPageButtonLocalizer`, `LastPageButtonLocalizer`, `ItemsPerPageLocalizer`, `ItemsLocalizer`, `NumbersOfItemsLocalizer` (1.6 to 2.4); the buttons and the filters: `New…`, `Edit…`, `Delete…`, `Save…`, `Cancel…`, `FilterMethod…Localizer` (the XML documentation lists those of the version).
   Not this: `ITextLocalizer<DataGrid<TItem>>.AddLanguageResource` with the culture "fr" changes nothing (the first resource of a culture wins, and Blazorise ships "fr"), and that localizer is one per item type.
3. The markup of the pager (icons, layout): its templates `FirstPageButtonTemplate`, `PreviousPageButtonTemplate`, `NextPageButtonTemplate`, `LastPageButtonTemplate`, `PageButtonTemplate` (`context.PageNumber`), `ItemsPerPageTemplate`, `TotalItemsTemplate` and `TotalItemsShortTemplate` (`context.TotalItems`), `PageSelectorTemplate`, `PageSizesTemplate` (`context.PageSize`, `context.PageSizes`); `PagerOptions` (`ButtonSize`, `PaginationPosition`, `TotalItemsPosition`), `PagerPosition`, `PageSizes`.
- The proof: a bUnit test that renders the page and finds « Suivante » and « éléments par page », when the test project has bUnit (the existing component tests show how Blazorise is registered there); otherwise a line of the checklist of the step.

## Replacing Blazorise with native Razor
One page or one family of components per step, its behavior unchanged and proved, the packages removed by the last step only.
1. The inventory, before any change: `git grep -c -E '<(DataGrid|DataGridColumn|TextEdit|TextInput|NumericEdit|NumericInput|DateEdit|DateInput|Select|Check|Switch|Button|Modal|Field|Validations?|Card|Row|Column|Icon|Tabs|Dropdown|Bar)\b' -- '*.razor'` (the tags of Blazorise start with a capital: `<select>` and `<button>` are HTML), and `git grep -n -E 'INotificationService|IMessageService|IModalService|IToastService|ITextLocalizer|AddBlazorise|ProductToken|_content/Blazorise' -- '*.cs' '*.razor' '*.cshtml' '*.html'`. The plan: the leaves first (icons, buttons, layout), then forms, dialogs and messages, then grids, then the registrations and the packages.
2. Each step: a test first that shows what the user sees (bUnit: headers, rows of the first page, texts of the pager, sort, validation messages), green on Blazorise, green again on the native version. Keep the columns and their order, the formats (culture), the default sort, the page size, the text of an empty list, the events (a click on a row), the authorizations.
3. The equivalents (Bootstrap markup, the CSS the application loads already):

| Blazorise | Native |
|---|---|
| `DataGrid`, `DataGridColumn Field Caption`, `ShowPager` | `<table class="table">` with Skip/Take (no package), or `QuickGrid Items` + `PropertyColumn Property Title Sortable` + `PaginationState { ItemsPerPage = 10 }` |
| `ReadData` (data paged by the server) | `ItemsProvider` of QuickGrid (`GridItemsProviderResult.From(items, totalItemCount)`) |
| `DataGridCommandColumn`, edit in the row | `TemplateColumn` with buttons; the edit in an `EditForm` |
| `TextInput`/`TextEdit`, `NumericInput`, `DateInput`, `Select`, `Check`, `Switch` | `InputText`, `InputNumber`, `InputDate`, `InputSelect`, `InputCheckbox` (`form-check form-switch`) in an `EditForm` |
| `Validations`, `Validation`, `ValidationRule` | `DataAnnotationsValidator`, `ValidationMessage`, the attributes of the model |
| `Field`, `FieldLabel`, `FieldHelp` | `<div class="mb-3">`, `<label class="form-label">`, `<div class="form-text">` |
| `Button Color="Color.Primary"`, `Badge`, `Alert`, `Card`, `Row`/`Column` | `<button type="button" class="btn btn-primary">`, `badge text-bg-…`, `alert alert-…`, `card`, `row`/`col-md-6` |
| `Modal`, `IModalService`, `IMessageService` | a component of the application: Bootstrap modal markup shown with `@if`, or `<dialog>`; a confirmation component |
| `INotificationService`, `IToastService` | a scoped toast service of the application and its component |
| `Icon Name="IconName.Edit"` | the CSS icons the application has (`<i class="bi bi-pencil" aria-hidden="true">`) |
| `Blazorise.Charts` | Chart.js through a small JS module: a step of its own |

   QuickGrid's own `Paginator` writes « Page 1 of 3 » and « Go to next page » in English (only `SummaryTemplate` changes): its French pager is a component of the application over `PaginationState`:
   ```razor
   @* FrenchPager.razor *@
   @using Microsoft.AspNetCore.Components.QuickGrid
   @implements IDisposable

   @if (State.TotalItemCount is int total)
   {
       <nav class="d-flex align-items-center gap-2" aria-label="Pagination">
           <button type="button" class="btn btn-sm btn-outline-secondary" disabled="@(!CanGoBack)" aria-label="Première page" @onclick="() => GoToAsync(0)">«</button>
           <button type="button" class="btn btn-sm btn-outline-secondary" disabled="@(!CanGoBack)" aria-label="Page précédente" @onclick="() => GoToAsync(State.CurrentPageIndex - 1)">‹</button>
           <span>Page @(State.CurrentPageIndex + 1) sur @(LastIndex + 1) · @total @(total > 1 ? "éléments" : "élément")</span>
           <button type="button" class="btn btn-sm btn-outline-secondary" disabled="@(!CanGoForward)" aria-label="Page suivante" @onclick="() => GoToAsync(State.CurrentPageIndex + 1)">›</button>
           <button type="button" class="btn btn-sm btn-outline-secondary" disabled="@(!CanGoForward)" aria-label="Dernière page" @onclick="() => GoToAsync(LastIndex)">»</button>
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
   ```razor
   <QuickGrid Items="@orders" Pagination="@pagination">
       <PropertyColumn Property="@(o => o.Number)" Title="Numéro" Sortable="true" />
       <PropertyColumn Property="@(o => o.Date)" Title="Date" Format="dd/MM/yyyy" Sortable="true" />
   </QuickGrid>
   <FrenchPager State="@pagination" />
   @code {
       private readonly PaginationState pagination = new() { ItemsPerPage = 10 };
   }
   ```
   Sorting and paging need an interactive render mode, as the DataGrid did.
4. A package is the developer's decision, never the coder's: QuickGrid (`Microsoft.AspNetCore.Components.QuickGrid`, Microsoft, MIT, its major version is the one of the target framework: 8.0.x for net8.0, 10.0.x for net10.0), bUnit for the tests. The analyst lists it in « Décisions », the free option first (a native table and the pager above need none); a step that needs it before it is there is « BLOQUÉ ».
5. The last step: no `Blazorise.*` PackageReference or PackageVersion left; in `Program.cs` no `AddBlazorise(…)`, `AddBootstrap5Providers()`, `AddFontAwesomeIcons()` (or the providers of the repository) nor `ProductToken` (a license token: never printed, never committed; the developer removes it from the configuration); in `_Imports.razor` no `@using Blazorise…`; in `App.razor`, `_Host.cshtml` or `index.html` no `_content/Blazorise…` link and no `ThemeProvider`, `MessageProvider`, `NotificationProvider`, `ModalProvider`, `ToastProvider`. Then `git grep -n -i blazorise` finds only the history of the documentation, the build and every test pass.
