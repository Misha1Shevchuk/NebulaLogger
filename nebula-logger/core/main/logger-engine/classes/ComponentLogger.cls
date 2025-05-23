//------------------------------------------------------------------------------------------------//
// This file is part of the Nebula Logger project, released under the MIT License.                //
// See LICENSE file or go to https://github.com/jongpie/NebulaLogger for full license details.    //
//------------------------------------------------------------------------------------------------//

/**
 * @group Logger Engine
 * @description Controller class used by the lightning web component `logger`
 * @see Logger
 * @see LogEntryEventBuilder
 */
@SuppressWarnings('PMD.ExcessivePublicCount, PMD.PropertyNamingConventions, PMD.StdCyclomaticComplexity')
public inherited sharing class ComponentLogger {
  @TestVisible
  private static final String LOGGER_COMPONENT_NAME {
    get {
      if (LOGGER_COMPONENT_NAME == null) {
        String namespace = String.isNotBlank(Logger.getNamespacePrefix()) ? Logger.getNamespacePrefix() : 'c';
        LOGGER_COMPONENT_NAME = namespace + '/logger';
      }
      return LOGGER_COMPONENT_NAME;
    }
    set;
  }

  private static final Map<String, Schema.SObjectField> LOG_ENTRY_EVENT_FIELD_NAME_TO_FIELD {
    get {
      if (LOG_ENTRY_EVENT_FIELD_NAME_TO_FIELD == null) {
        LOG_ENTRY_EVENT_FIELD_NAME_TO_FIELD = Schema.LogEntryEvent__e.SObjectType.getDescribe().fields.getMap();
      }
      return LOG_ENTRY_EVENT_FIELD_NAME_TO_FIELD;
    }
    set;
  }

  static {
    LoggerStackTrace.ignoreOrigin(ComponentLogger.class);
    LoggerStackTrace.ignoreOrigin(LoggerStackTrace.SourceLanguage.JavaScript, LOGGER_COMPONENT_NAME);
  }

  /**
   * @description Provides data to the frontend about `LoggerSettings__c` & server-supported logging details
   * @return   return The instance of `ComponentLoggerSettings` for the current user
   */
  @AuraEnabled(cacheable=true)
  public static ComponentLoggerSettings getSettings() {
    return new ComponentLoggerSettings();
  }

  /**
   * @description saveComponentLogEntries Saves log entries created via lwc or aura components
   * @param  componentLogEntries The list of `ComponentLogEntry` objects to save via `Logger`
   * @param  saveMethodName      String name of the instance of Logger.SaveMethod to use when saving.
   *                             When null, the value of `Logger.getSaveMethod()` will be used.
   * @return                     return The transaction ID (based on `Logger.getTransactionId())`
   */
  @AuraEnabled
  public static String saveComponentLogEntries(List<ComponentLogEntry> componentLogEntries, String saveMethodName) {
    try {
      Logger.SaveMethod saveMethod = Logger.getSaveMethod();
      for (ComponentLogEntry componentLogEntry : componentLogEntries) {
        Logger.setScenario(componentLogEntry.scenario);
        System.LoggingLevel entryLoggingLevel = Logger.getLoggingLevel(componentLogEntry.loggingLevel);
        LogEntryEventBuilder logEntryEventBuilder = Logger.newEntry(entryLoggingLevel, componentLogEntry.message);

        if (logEntryEventBuilder.shouldSave() == false) {
          continue;
        }

        Map<Schema.SObjectField, Object> customFieldToFieldValue = getCustomFieldToFieldValue(componentLogEntry.fieldToValue);
        LogEntryEvent__e logEntryEvent = logEntryEventBuilder.setTimestamp(componentLogEntry.timestamp)
          .setField(customFieldToFieldValue)
          .addTags(componentLogEntry.tags)
          .getLogEntryEvent();

        if (componentLogEntry.recordId != null) {
          logEntryEventBuilder.setRecord(componentLogEntry.recordId);
        }
        if (componentLogEntry.record != null) {
          logEntryEventBuilder.setRecord(componentLogEntry.record);
        }

        setBrowserDetails(logEntryEvent, componentLogEntry);
        setComponentErrorDetails(logEntryEvent, componentLogEntry.error);
        setOriginStackTraceDetails(logEntryEvent, componentLogEntry.originStackTrace);
      }
      if (String.isNotBlank(saveMethodName)) {
        saveMethod = Logger.SaveMethod.valueOf(saveMethodName);
      }
      Logger.saveLog(saveMethod);
      return Logger.getTransactionId();
    } catch (System.Exception apexException) {
      String errorMessage = apexException.getMessage() + '\n' + apexException.getStackTraceString();
      System.AuraHandledException auraException = new System.AuraHandledException(errorMessage);
      auraException.setMessage(errorMessage);
      throw auraException;
    }
  }

  private static Map<Schema.SObjectField, Object> getCustomFieldToFieldValue(Map<String, Object> fieldNameToValue) {
    Map<Schema.SObjectField, Object> resolvedFieldToFieldValue = new Map<Schema.SObjectField, Object>();

    if (fieldNameToValue == null || fieldNameToValue.isEmpty()) {
      return resolvedFieldToFieldValue;
    }

    for (String fieldName : fieldNameToValue.keySet()) {
      Schema.SObjectField field = LOG_ENTRY_EVENT_FIELD_NAME_TO_FIELD.get(fieldName);
      if (field != null) {
        resolvedFieldToFieldValue.put(field, fieldNameToValue.get(fieldName));
      }
    }
    return resolvedFieldToFieldValue;
  }

  private static void setBrowserDetails(LogEntryEvent__e logEntryEvent, ComponentLogEntry componentLogEntry) {
    logEntryEvent.BrowserAddress__c = LoggerDataStore.truncateFieldValue(Schema.LogEntryEvent__e.BrowserAddress__c, componentLogEntry.browser?.address);
    logEntryEvent.BrowserFormFactor__c = LoggerDataStore.truncateFieldValue(
      Schema.LogEntryEvent__e.BrowserFormFactor__c,
      componentLogEntry.browser?.formFactor
    );
    logEntryEvent.BrowserLanguage__c = LoggerDataStore.truncateFieldValue(Schema.LogEntryEvent__e.BrowserLanguage__c, componentLogEntry.browser?.language);
    logEntryEvent.BrowserScreenResolution__c = LoggerDataStore.truncateFieldValue(
      Schema.LogEntryEvent__e.BrowserScreenResolution__c,
      componentLogEntry.browser?.screenResolution
    );
    // TODO BrowserUrl__c is deprecated (replaced by BrowserAddress__c), but keep setting BrowserUrl__c for now so people have time to migrate to referencing BrowserAddress__c
    logEntryEvent.BrowserUrl__c = LoggerDataStore.truncateFieldValue(Schema.LogEntryEvent__e.BrowserUrl__c, componentLogEntry.browser?.address);
    logEntryEvent.BrowserUserAgent__c = LoggerDataStore.truncateFieldValue(Schema.LogEntryEvent__e.BrowserUserAgent__c, componentLogEntry.browser?.userAgent);
    logEntryEvent.BrowserWindowResolution__c = LoggerDataStore.truncateFieldValue(
      Schema.LogEntryEvent__e.BrowserWindowResolution__c,
      componentLogEntry.browser?.windowResolution
    );
  }

  private static void setComponentErrorDetails(LogEntryEvent__e logEntryEvent, ComponentError componentError) {
    if (componentError == null) {
      return;
    }

    logEntryEvent.ExceptionMessage__c = componentError.message;
    logEntryEvent.ExceptionType__c = componentError.type;

    LoggerStackTrace.SourceLanguage language = LoggerStackTrace.SourceLanguage.JavaScript;
    // All exception classes in Apex must end in 'Exception'
    if (componentError.type?.endsWith('Exception') == true) {
      language = LoggerStackTrace.SourceLanguage.Apex;
    }

    if (componentError.stackTrace == null) {
      return;
    }

    logEntryEvent.ExceptionLocation__c = LoggerDataStore.truncateFieldValue(
      Schema.LogEntryEvent__e.ExceptionLocation__c,
      componentError.stackTrace.componentName + '.' + componentError.stackTrace.functionName
    );
    logEntryEvent.ExceptionSourceActionName__c = LoggerDataStore.truncateFieldValue(
      Schema.LogEntryEvent__e.ExceptionSourceActionName__c,
      componentError.stackTrace.functionName
    );
    logEntryEvent.ExceptionSourceApiName__c = LoggerDataStore.truncateFieldValue(
      Schema.LogEntryEvent__e.ExceptionSourceApiName__c,
      componentError.stackTrace.componentName
    );
    logEntryEvent.ExceptionSourceMetadataType__c = LoggerDataStore.truncateFieldValue(
      Schema.LogEntryEvent__e.ExceptionSourceMetadataType__c,
      componentError.stackTrace.metadataType
    );
    logEntryEvent.ExceptionStackTrace__c = LoggerDataStore.truncateFieldValue(
      Schema.LogEntryEvent__e.ExceptionStackTrace__c,
      componentError.stackTrace.ParsedStackTraceString
    );
  }

  private static void setOriginStackTraceDetails(LogEntryEvent__e logEntryEvent, ComponentStackTrace originStackTrace) {
    logEntryEvent.OriginType__c = 'Component';

    if (originStackTrace == null) {
      logEntryEvent.StackTrace__c = null;
      return;
    }

    // Older, custom convention used for a 'type', with values 'Aura' and 'LWC'
    String componentType;
    if (originStackTrace.metadataType == LoggerStackTrace.SourceMetadataType.AuraDefinitionBundle.name()) {
      componentType = 'Aura';
    } else if (originStackTrace.metadataType == LoggerStackTrace.SourceMetadataType.LightningComponentBundle.name()) {
      componentType = 'LWC';
    }

    // Legacy fields (OriginType__c is considered legacy, even though it uses the 'Origin' prefix)
    logEntryEvent.ComponentType__c = componentType;

    // New Origin fields
    logEntryEvent.OriginLocation__c = LoggerDataStore.truncateFieldValue(
      Schema.LogEntryEvent__e.OriginLocation__c,
      originStackTrace.componentName + '.' + originStackTrace.functionName
    );
    logEntryEvent.OriginSourceActionName__c = LoggerDataStore.truncateFieldValue(
      Schema.LogEntryEvent__e.OriginSourceActionName__c,
      originStackTrace.functionName
    );
    logEntryEvent.OriginSourceApiName__c = LoggerDataStore.truncateFieldValue(Schema.LogEntryEvent__e.OriginSourceApiName__c, originStackTrace.componentName);
    logEntryEvent.OriginSourceMetadataType__c = LoggerDataStore.truncateFieldValue(
      Schema.LogEntryEvent__e.OriginSourceMetadataType__c,
      originStackTrace.metadataType
    );
    logEntryEvent.StackTrace__c = LoggerDataStore.truncateFieldValue(Schema.LogEntryEvent__e.StackTrace__c, originStackTrace.parsedStackTraceString);
  }

  /**
   * @description A DTO object used for passing `LoggerSettings__c` details to lightning components
   */
  public class ComponentLoggerSettings {
    /**
     * @description Indicates the save method that will be used by default if no other save method is specified, based on `LoggerSettings__c.DefaultSaveMethod__c`
     */
    @AuraEnabled
    public String defaultSaveMethodName { get; set; }

    /**
     * @description Indicates if logging is enabled for the current user, based on `LoggerSettings__c.IsEnabled__c`
     */
    @AuraEnabled
    public Boolean isEnabled { get; set; }

    /**
     * @description Indicates if logging via the browser's `console.log()` is enabled for the current user, based on `LoggerSettings__c.IsJavaScriptConsoleLoggingEnabled__c`
     */
    @AuraEnabled
    public Boolean isConsoleLoggingEnabled { get; set; }

    /**
     * @description Indicates if logging via the standard LWC `lightning-logger` is enabled for the current user, based on `LoggerSettings__c.IsJavaScriptLightningLoggerEnabled__c`
     */
    @AuraEnabled
    public Boolean isLightningLoggerEnabled { get; set; }

    /**
     * @description A map of the supported `LoggingLevel` enum values
     */
    @AuraEnabled
    public Map<String, Integer> supportedLoggingLevels { get; set; }

    /**
     * @description The configured `LoggingLevel` for the current user, based on `LoggerSettings__c.LoggingLevel__c`
     */
    @AuraEnabled
    public ComponentLoggingLevel userLoggingLevel { get; set; }

    private ComponentLoggerSettings() {
      LoggerSettings__c userSettings = Logger.getUserSettings();

      this.defaultSaveMethodName = Logger.getSaveMethod().name();
      this.isEnabled = userSettings.IsEnabled__c;
      this.isConsoleLoggingEnabled = userSettings.IsJavaScriptConsoleLoggingEnabled__c;
      this.isLightningLoggerEnabled = userSettings.IsJavaScriptLightningLoggerEnabled__c;
      this.supportedLoggingLevels = getSupportedLoggingLevels();
      this.userLoggingLevel = getUserLoggingLevel();
    }

    private Map<String, Integer> getSupportedLoggingLevels() {
      return new Map<String, Integer>{
        System.LoggingLevel.ERROR.name() => System.LoggingLevel.ERROR.ordinal(),
        System.LoggingLevel.WARN.name() => System.LoggingLevel.WARN.ordinal(),
        System.LoggingLevel.INFO.name() => System.LoggingLevel.INFO.ordinal(),
        System.LoggingLevel.DEBUG.name() => System.LoggingLevel.DEBUG.ordinal(),
        System.LoggingLevel.FINE.name() => System.LoggingLevel.FINE.ordinal(),
        System.LoggingLevel.FINER.name() => System.LoggingLevel.FINER.ordinal(),
        System.LoggingLevel.FINEST.name() => System.LoggingLevel.FINEST.ordinal()
      };
    }

    private ComponentLoggingLevel getUserLoggingLevel() {
      return new ComponentLoggingLevel(Logger.getUserLoggingLevel());
    }
  }

  /**
   * @description A DTO object used for passing `LoggingLevel` details to lightning components
   */
  public class ComponentLoggingLevel {
    /**
     * @description The name of the `LoggingLevel` enum value
     */
    @AuraEnabled
    public String name { get; set; }

    /**
     * @description The ordinal of the `LoggingLevel` enum value
     */
    @AuraEnabled
    public Integer ordinal { get; set; }

    private ComponentLoggingLevel(System.LoggingLevel loggingLevel) {
      this.name = loggingLevel.name();
      this.ordinal = loggingLevel.ordinal();
    }
  }

  /**
   * @description A DTO object used to create log entries for lightning components
   */
  public class ComponentLogEntry {
    /**
     * @description Context about the user's browser, automatically captured by Nebula Logger
     */
    @AuraEnabled
    public ComponentBrowserContext browser { get; set; }

    /**
     * @description (Optional) A JavaScript Error to log
     */
    @AuraEnabled
    public ComponentError error { get; set; }

    /**
     * @description (Optional) A map containing key-value pairs of fields to set on `LogEntryEvent__e`
     */
    @AuraEnabled
    public Map<String, Object> fieldToValue { get; set; }
    /**
     * @description The name of the `LoggingLevel` enum value
     */
    @AuraEnabled
    public String loggingLevel { get; set; }

    /**
     * @description The value to use as the log entry's message
     */
    @AuraEnabled
    public String message { get; set; }

    /**
     * @description Contains details about the origin of the component log entry
     */
    @AuraEnabled
    public ComponentStackTrace originStackTrace { get; set; }

    /**
     * @description (Optional) The record ID to relate to the log entry
     */
    @AuraEnabled
    public Id recordId { get; set; }

    /**
     * @description (Optional) The record to relate to the log entry - the record's JSON is also stored
     */
    @AuraEnabled
    public SObject record { get; set; }

    /**
     * @description Optionally specify the name to use for the current transaction's scenario
     */
    @AuraEnabled
    public String scenario { get; set; }

    /**
     * @description `DEPRECATED` This property is no longer used, and will be removed in a future release.
     *              The JavaScript stack trace from when the log entry was created
     */
    @AuraEnabled
    public String stack { get; set; }

    /**
     * @description The datetime that the log entry was created in the lightning component
     */
    @AuraEnabled
    public Datetime timestamp { get; set; }

    /**
     * @description (Optional) A list of tags to associate with the log entry
     */
    @AuraEnabled
    public List<String> tags { get; set; }
  }

  /**
   * @description A DTO object used to log details about the user's browser
   */
  public class ComponentBrowserContext {
    /**
     * @description The URL displayed in the user's browser
     */
    @AuraEnabled
    public String address { get; set; }

    /**
     * @description The form factor of the user's browser
     */
    @AuraEnabled
    public String formFactor { get; set; }

    /**
     * @description The language set in the user's browser
     */
    @AuraEnabled
    public String language { get; set; }

    /**
     * @description The resolution of the user's device
     */
    @AuraEnabled
    public String screenResolution { get; set; }

    /**
     * @description The user agent of the user's browser
     */
    @AuraEnabled
    public String userAgent { get; set; }

    /**
     * @description The resolution of the user's browser window
     */
    @AuraEnabled
    public String windowResolution { get; set; }
  }

  /**
   * @description A DTO object used to log details about a JavaScript error
   */
  public class ComponentError {
    /**
     * @description The error's message
     */
    @AuraEnabled
    public String message { get; set; }

    /**
     * @description `DEPRECATED` This property is no longer used, and will be removed in a future release.
     *              The error's stack trace string
     */
    @AuraEnabled
    public String stack { get; set; }

    /**
     * @description Contains details about the origin of the error
     */
    @AuraEnabled
    public ComponentStackTrace stackTrace { get; set; }

    /**
     * @description The type of JavaScript error
     */
    @AuraEnabled
    public String type { get; set; }
  }

  /**
   * @description A DTO object used to log details about the origin of a JavaScript log entry
   */
  public class ComponentStackTrace {
    /**
     * @description The component that generated the log entry
     */
    @AuraEnabled
    public String componentName { get; set; }

    /**
     * @description The component's function that generated the log entry
     */
    @AuraEnabled
    public String functionName { get; set; }

    /**
     * @description The metadata type of the component that generated the log entry
     *              Possible values are `AuraDefinitionBundle` and `LightningComponentBundle`
     */
    @AuraEnabled
    public String metadataType { get; set; }

    /**
     * @description The parsed stack trace used to determine the log entry origin
     */
    @AuraEnabled
    public String parsedStackTraceString { get; set; }
  }
}
