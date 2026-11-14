/// Keys for persisted properties.
enum TxlemetryPersistedProperty {
  anonymousId('anonymous_id'),
  distinctId('distinct_id'),
  deviceId('device_id'),
  props('props'),
  enablePersonProcessing('enable_person_processing'),
  personMode('person_mode'),
  featureFlagDetails('feature_flag_details'),
  optedOut('opted_out'),
  personProperties('person_properties'),
  groupProperties('group_properties');

  final String key;
  const TxlemetryPersistedProperty(this.key);
}
