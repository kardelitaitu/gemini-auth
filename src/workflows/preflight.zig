const std = @import("std");
const cli = @import("../cli/root.zig");
const registry = @import("../registry/root.zig");
const account_names = @import("account_names.zig");
const targets = @import("targets.zig");
const workflow_env = @import("env.zig");

const skip_service_reconcile_env = workflow_env.skip_service_reconcile_env;
const hasNonEmptyEnvVar = workflow_env.hasNonEmptyEnvVar;
const ForegroundUsageRefreshTarget = targets.ForegroundUsageRefreshTarget;
const LiveTtyTarget = targets.LiveTtyTarget;
const liveTtyPreflightError = targets.liveTtyPreflightError;
const shouldRefreshForegroundUsage = targets.shouldRefreshForegroundUsage;
const ForegroundUsageOutcome = account_names.ForegroundUsageOutcome;
const ForegroundUsageRefreshState = account_names.ForegroundUsageRefreshState;
const max_usage_override_display_width = account_names.max_usage_override_display_width;
const formatStatusOverrideAlloc = account_names.formatStatusOverrideAlloc;
const refreshForegroundUsageForDisplayWithApiFetcher = account_names.refreshForegroundUsageForDisplayWithApiFetcher;
const refreshForegroundUsageForDisplayWithApiFetcherWithPoolInit = account_names.refreshForegroundUsageForDisplayWithApiFetcherWithPoolInit;
const initForegroundUsagePool = account_names.initForegroundUsagePool;
const maybeRefreshForegroundAccountNames = account_names.maybeRefreshForegroundAccountNames;
const maybeSpawnBackgroundAccountNameRefresh = account_names.maybeSpawnBackgroundAccountNameRefresh;
const refreshAccountNamesAfterLogin = account_names.refreshAccountNamesAfterLogin;
const refreshAccountNamesAfterSwitch = account_names.refreshAccountNamesAfterSwitch;
const refreshAccountNamesForList = account_names.refreshAccountNamesForList;
const shouldRefreshTeamAccountNamesForUserScopeWithAccountApiEnabled = account_names.shouldRefreshTeamAccountNamesForUserScopeWithAccountApiEnabled;
const shouldScheduleBackgroundAccountNameRefresh = account_names.shouldScheduleBackgroundAccountNameRefresh;
const runBackgroundAccountNameRefresh = account_names.runBackgroundAccountNameRefresh;
const runBackgroundAccountNameRefreshWithLockAcquirer = account_names.runBackgroundAccountNameRefreshWithLockAcquirer;
const loadActiveAuthInfoForAccountRefresh = account_names.loadActiveAuthInfoForAccountRefresh;
const loadSingleFileImportAuthInfo = account_names.loadSingleFileImportAuthInfo;
const reconcileActiveAuthAfterRemove = account_names.reconcileActiveAuthAfterRemove;
const trackedActiveAccountKey = account_names.trackedActiveAccountKey;
const loadCurrentAuthState = account_names.loadCurrentAuthState;
const selectionContainsAccountKey = account_names.selectionContainsAccountKey;
const selectionContainsIndex = account_names.selectionContainsIndex;
const selectBestRemainingAccountKeyByUsageAlloc = account_names.selectBestRemainingAccountKeyByUsageAlloc;
const resolveSwitchQueryLocally = targets.resolveSwitchQueryLocally;
const findMatchingAccounts = targets.findMatchingAccounts;
const findMatchingAccountsForRemove = targets.findMatchingAccountsForRemove;
const findAccountIndexByDisplayNumber = targets.findAccountIndexByDisplayNumber;
const isHandledCliError = preflight.isHandledCliError;
const shouldReconcileManagedService = preflight.shouldReconcileManagedService;
const ensureLiveTty = preflight.ensureLiveTty;
const apiModeUsesApi = preflight.apiModeUsesApi;
const ensureForegroundNodeAvailableWithApiEnabled = preflight.ensureForegroundNodeAvailableWithApiEnabled;
const switch_live_default_refresh_interval_ms = preflight.switch_live_default_refresh_interval_ms;
const SwitchLiveRefreshPolicy = preflight.SwitchLiveRefreshPolicy;
const SwitchLiveRuntime = preflight.SwitchLiveRuntime;
const switchLiveRuntimeMaybeStartRefresh = preflight.switchLiveRuntimeMaybeStartRefresh;
const switchLiveRuntimeMaybeTakeUpdatedDisplay = preflight.switchLiveRuntimeMaybeTakeUpdatedDisplay;
const switchLiveRuntimeBuildStatusLine = preflight.switchLiveRuntimeBuildStatusLine;
const findAccountIndexByAccountKeyConst = preflight.findAccountIndexByAccountKeyConst;
const replaceOptionalOwnedString = preflight.replaceOptionalOwnedString;
const mapSwitchUsageOverridesToLatest = preflight.mapSwitchUsageOverridesToLatest;
const mergeSwitchLiveRefreshIntoLatest = preflight.mergeSwitchLiveRefreshIntoLatest;
const buildSwitchLiveActionDisplay = preflight.buildSwitchLiveActionDisplay;
const buildRemoveLiveActionDisplay = preflight.buildRemoveLiveActionDisplay;
const loadStoredSwitchSelectionDisplay = preflight.loadStoredSwitchSelectionDisplay;
const loadStoredSwitchSelectionDisplayWithRefreshError = preflight.loadStoredSwitchSelectionDisplayWithRefreshError;
const loadInitialLiveSelectionDisplay = preflight.loadInitialLiveSelectionDisplay;
const loadSwitchSelectionDisplay = preflight.loadSwitchSelectionDisplay;
const removeSelectedAccountsAndPersist = preflight.removeSelectedAccountsAndPersist;
const switchLiveRuntimeApplySelection = preflight.switchLiveRuntimeApplySelection;
const removeLiveRuntimeApplySelection = preflight.removeLiveRuntimeApplySelection;
const HelpConfig = help_workflow.HelpConfig;
const loadHelpConfig = help_workflow.loadHelpConfig;

pub fn isHandledCliError(err: anyerror) bool {
    return err == error.AccountNotFound or
        err == error.InvalidCliUsage or
        err == error.SwitchRequiresTty or
        err == error.RemoveRequiresTty or
        err == error.TuiRequiresTty or
        err == error.InvalidRemoveSelectionInput or
        err == error.GeminiLoginFailed or
        err == error.NodeJsRequired or
        err == error.ListRequiresTty;
}

pub fn apiModeUsesApi(default_enabled: bool, api_mode: cli.types.ApiMode) bool {
    return switch (api_mode) {
        .default => default_enabled,
        .force_api => true,
        .skip_api => false,
    };
}

pub fn ensureForegroundNodeAvailableWithApiEnabled(
    allocator: std.mem.Allocator,
    usage_api_enabled: bool,
    account_api_enabled: bool,
) !void {
    // Gemini doesn't need Node.js for API calls like OpenAI did
    // Keeping function for compatibility but simplified
    _ = allocator;
    _ = usage_api_enabled;
    _ = account_api_enabled;
}

pub fn shouldReconcileManagedService(cmd: cli.types.Command) bool {
    if (hasNonEmptyEnvVar(skip_service_reconcile_env)) return false;
    return switch (cmd) {
        .help, .version, .status => false,
        else => true,
    };
}
