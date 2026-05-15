import * as chrono from "chrono-node";

function componentPayload(components) {
  if (!components) {
    return null;
  }
  const names = ["year", "month", "day", "weekday", "hour", "minute", "second", "millisecond", "timezoneOffset"];
  const values = {};
  for (const name of names) {
    const value = components.get(name);
    if (value !== null && value !== undefined) {
      values[name] = {
        value,
        certain: components.isCertain(name)
      };
    }
  }
  return {
    iso: components.date().toISOString(),
    values
  };
}

globalThis.CalShotChrono = {
  parse(text, refDateISO, timezoneOffsetMinutes) {
    const reference = {
      instant: new Date(refDateISO)
    };
    if (typeof timezoneOffsetMinutes === "number" && Number.isFinite(timezoneOffsetMinutes)) {
      reference.timezone = timezoneOffsetMinutes;
    }

    return chrono.parse(text, reference, { forwardDate: true }).map((result) => ({
      index: result.index,
      text: result.text,
      start: componentPayload(result.start),
      end: componentPayload(result.end)
    }));
  }
};

