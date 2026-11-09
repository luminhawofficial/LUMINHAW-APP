export type ReceiptOcrResult = {
  referenceNumber: string | null;
  transactionDate: string | null;
  transactionTime: string | null;
  amountCentavos: number | null;
  recipient: string | null;
  transactionStatus: "successful" | "failed" | "unknown";
  providerIdentification: "gcash" | "ambiguous" | "other" | "unknown";
  hasTransactionMarkers: boolean;
  isGcashReceipt: boolean;
  confidence: number | null;
  imageWidth: number | null;
  imageHeight: number | null;
};

export type ReceiptChecks = {
  validImage: boolean;
  isGcashReceipt: boolean;
  imageReadable: boolean;
  referenceMatch: boolean;
  amountMatch: boolean;
  dateMatch: boolean;
  timeMatch: boolean;
  duplicateReference: boolean;
};

export type ReceiptClassification = {
  status: "matched" | "manual_review" | "rejected" | "inconclusive";
  reason: string | null;
  errorCode: string | null;
  checks: ReceiptChecks;
};

type ImageInspection = {
  valid: boolean;
  mimeType: "image/jpeg" | "image/png" | null;
  width: number | null;
  height: number | null;
};

function uint32be(bytes: Uint8Array, offset: number): number {
  return new DataView(
    bytes.buffer,
    bytes.byteOffset,
    bytes.byteLength,
  ).getUint32(offset, false);
}

function uint16be(bytes: Uint8Array, offset: number): number {
  return new DataView(
    bytes.buffer,
    bytes.byteOffset,
    bytes.byteLength,
  ).getUint16(offset, false);
}

export function inspectReceiptImage(bytes: Uint8Array): ImageInspection {
  if (bytes.length < 24 || bytes.length > 5 * 1024 * 1024) {
    return { valid: false, mimeType: null, width: null, height: null };
  }

  const pngSignature = [
    0x89,
    0x50,
    0x4e,
    0x47,
    0x0d,
    0x0a,
    0x1a,
    0x0a,
  ];
  if (pngSignature.every((byte, index) => bytes[index] === byte)) {
    if (
      String.fromCharCode(...bytes.slice(12, 16)) !== "IHDR" ||
      uint32be(bytes, 8) !== 13
    ) {
      return { valid: false, mimeType: null, width: null, height: null };
    }
    const width = uint32be(bytes, 16);
    const height = uint32be(bytes, 20);
    let offset = 8;
    let foundEnd = false;
    let foundImageData = false;
    while (offset + 12 <= bytes.length) {
      const length = uint32be(bytes, offset);
      if (length > bytes.length - offset - 12) break;
      const type = String.fromCharCode(...bytes.slice(offset + 4, offset + 8));
      if (type === "IDAT" && length > 0) foundImageData = true;
      offset += length + 12;
      if (type === "IEND") {
        foundEnd = length === 0 && offset === bytes.length;
        break;
      }
    }
    return {
      valid: width > 0 && height > 0 && width <= 12_000 && height <= 12_000 &&
        width * height <= 50_000_000 && foundImageData && foundEnd,
      mimeType: "image/png",
      width,
      height,
    };
  }

  if (bytes[0] !== 0xff || bytes[1] !== 0xd8) {
    return { valid: false, mimeType: null, width: null, height: null };
  }
  let offset = 2;
  let width: number | null = null;
  let height: number | null = null;
  let foundScan = false;
  while (offset + 4 <= bytes.length) {
    if (bytes[offset] !== 0xff) break;
    while (offset < bytes.length && bytes[offset] === 0xff) offset++;
    const marker = bytes[offset++];
    if (marker === 0xd9) break;
    if (marker === 0xda) {
      foundScan = true;
      break;
    }
    if (marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) continue;
    if (offset + 2 > bytes.length) break;
    const segmentLength = uint16be(bytes, offset);
    if (segmentLength < 2 || offset + segmentLength > bytes.length) break;
    if (
      (marker >= 0xc0 && marker <= 0xc3) ||
      (marker >= 0xc5 && marker <= 0xc7) ||
      (marker >= 0xc9 && marker <= 0xcb) ||
      (marker >= 0xcd && marker <= 0xcf)
    ) {
      if (segmentLength < 7) break;
      height = uint16be(bytes, offset + 3);
      width = uint16be(bytes, offset + 5);
    }
    offset += segmentLength;
  }
  const hasEndMarker = bytes[bytes.length - 2] === 0xff &&
    bytes[bytes.length - 1] === 0xd9;
  return {
    valid: hasEndMarker && foundScan && width !== null && height !== null &&
      width > 0 && height > 0 && width <= 12_000 && height <= 12_000 &&
      width * height <= 50_000_000,
    mimeType: "image/jpeg",
    width,
    height,
  };
}

export function isSupportedImage(bytes: Uint8Array): boolean {
  return inspectReceiptImage(bytes).valid;
}

export function normalizeReference(value: string): string {
  return value.replace(/[^0-9]/g, "");
}

function extractReference(text: string): string | null {
  const match = text.match(
    /\b(?:transaction\s*)?(?:reference|ref)\.?\s*(?:(?:number|no)\.?)?\s*[:#-]?\s*([0-9][0-9\s-]{11,24})/i,
  );
  if (!match) return null;
  const reference = normalizeReference(match[1]);
  return /^\d{13}$/.test(reference) ? reference : null;
}

function formatReference(value: string): string {
  const digits = normalizeReference(value);
  return /^\d{13}$/.test(digits)
    ? `${digits.slice(0, 4)} ${digits.slice(4, 7)} ${digits.slice(7)}`
    : value;
}

const notGcashReceiptMessage =
  "The uploaded image does not appear to be a GCash receipt. Please upload or take a clear picture of your official GCash receipt.";
const unreadableReceiptMessage =
  "The receipt is blurry or the transaction details cannot be read clearly. Please take a clear, well-lit photo of the receipt, or send it to luminhawofficial@gmail.com for assistance.";

function extractDate(text: string): string | null {
  const patterns = [
    /\b(20\d{2})[-/.](\d{1,2})[-/.](\d{1,2})\b/,
    /\b(\d{1,2})[-/.](\d{1,2})[-/.](20\d{2})\b/,
    /\b(Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:tember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\s+(\d{1,2}),?\s+(20\d{2})\b/i,
    /\b(\d{1,2})\s+(Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:tember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\s+(20\d{2})\b/i,
  ];
  for (const [index, pattern] of patterns.entries()) {
    const match = text.match(pattern);
    if (!match) continue;
    let year: number;
    let month: number;
    let day: number;
    if (index === 0) {
      year = Number(match[1]);
      month = Number(match[2]);
      day = Number(match[3]);
    } else if (index === 1) {
      month = Number(match[1]);
      day = Number(match[2]);
      year = Number(match[3]);
    } else {
      const monthText = index === 2 ? match[1] : match[2];
      const monthNames = [
        "jan",
        "feb",
        "mar",
        "apr",
        "may",
        "jun",
        "jul",
        "aug",
        "sep",
        "oct",
        "nov",
        "dec",
      ];
      month = monthNames.indexOf(monthText.slice(0, 3).toLowerCase()) + 1;
      day = Number(index === 2 ? match[2] : match[1]);
      year = Number(match[3]);
    }
    const parsed = new Date(Date.UTC(year, month - 1, day));
    if (
      parsed.getUTCFullYear() === year &&
      parsed.getUTCMonth() === month - 1 &&
      parsed.getUTCDate() === day
    ) {
      return `${year.toString().padStart(4, "0")}-${
        month.toString().padStart(2, "0")
      }-${day.toString().padStart(2, "0")}`;
    }
  }
  return null;
}

function extractTime(text: string): string | null {
  const match = text.match(
    /\b((?:0?[1-9]|1[0-2]):[0-5]\d\s?(?:AM|PM)|(?:[01]\d|2[0-3]):[0-5]\d)\b/i,
  );
  return match?.[1]?.replace(/\s+/g, " ").trim().toUpperCase() ?? null;
}

function normalizeTime(value: string | null): string | null {
  if (!value) return null;
  const match = value.match(/^\s*(\d{1,2}):([0-5]\d)\s*(AM|PM)?\s*$/i);
  if (!match) return null;
  let hour = Number(match[1]);
  const minute = Number(match[2]);
  const meridiem = match[3]?.toUpperCase();
  if (meridiem) {
    if (hour < 1 || hour > 12) return null;
    hour = hour % 12 + (meridiem === "PM" ? 12 : 0);
  } else if (hour > 23) {
    return null;
  }
  return `${hour.toString().padStart(2, "0")}:${
    minute.toString().padStart(2, "0")
  }`;
}

function extractAmount(text: string): number | null {
  const match = text.match(/(?:PHP|₱)\s*([\d,]+(?:\.\d{1,2})?)/i);
  if (!match) return null;
  const value = Number(match[1].replace(/,/g, ""));
  return Number.isFinite(value) && value > 0 ? Math.round(value * 100) : null;
}

function extractRecipient(text: string): string | null {
  const match = text.match(
    /(?:sent\s+to|paid\s+to|recipient)\s*[:\-]?\s*([^\r\n]{2,100})/i,
  );
  return match?.[1]?.trim() ?? null;
}

export function parseReceiptText(
  text: string,
  confidence: number | null,
  imageWidth: number | null = null,
  imageHeight: number | null = null,
): ReceiptOcrResult {
  const lowered = text.toLowerCase();
  const failedStatus =
    /\b(?:transaction|payment)\s+(?:status\s*[:\-]?\s*)?(?:failed|unsuccessful|cancelled|canceled)\b/
      .test(lowered);
  const transactionStatus = failedStatus
    ? "failed"
    : /\b(?:transaction|payment)\s+(?:status\s*[:\-]?\s*)?(?:successful|completed)\b|\b(?:sent successfully|successfully sent|payment sent)\b/
        .test(lowered)
    ? "successful"
    : "unknown";
  const providerText = text.split(/\r?\n/)
    .filter((line) => !/^\s*(?:recipient|sent to|paid to)\b/i.test(line))
    .join("\n");
  const hasTransactionMarker =
    /\b(?:transaction|payment|receipt|sent successfully|successfully sent)\b/i
      .test(text) &&
    /\b(?:reference|ref(?:erence)?\s*(?:no|number)|amount|date)\b/i.test(text);
  const providerIdentification: ReceiptOcrResult["providerIdentification"] =
    /\bg\s*c\s*a\s*s\s*h\b/i.test(providerText)
      ? "gcash"
      : /\bg\s*c\s*(?:a|4)\s*(?:s|5|\$)\s*h\b/i.test(
          providerText,
        )
      ? "ambiguous"
      : /\b(?:maya|paymaya|grabpay|shopeepay|gotyme|mari?bank)\b/i.test(
          providerText,
        )
      ? "other"
      : "unknown";
  return {
    referenceNumber: extractReference(text),
    transactionDate: extractDate(text),
    transactionTime: extractTime(text),
    amountCentavos: extractAmount(text),
    recipient: extractRecipient(text),
    transactionStatus,
    providerIdentification,
    hasTransactionMarkers: hasTransactionMarker,
    isGcashReceipt: providerIdentification === "gcash" &&
      hasTransactionMarker,
    confidence,
    imageWidth,
    imageHeight,
  };
}

export async function readGcashReceipt(
  imageBytes: Uint8Array,
  apiKey: string,
  fetcher: typeof fetch = fetch,
  timeoutMilliseconds = 20_000,
): Promise<ReceiptOcrResult> {
  const image = inspectReceiptImage(imageBytes);
  if (!image.valid || !image.mimeType) {
    throw new Error("invalid_receipt_image");
  }
  const imageCopy = new Uint8Array(imageBytes.byteLength);
  imageCopy.set(imageBytes);
  const form = new FormData();
  const extension = image.mimeType === "image/png" ? "png" : "jpg";
  form.append(
    "file",
    new Blob([imageCopy.buffer], { type: image.mimeType }),
    `receipt.${extension}`,
  );
  form.append("OCREngine", "2");
  let response: Response;
  try {
    response = await fetcher("https://api.ocr.space/parse/image", {
      method: "POST",
      headers: { apikey: apiKey },
      body: form,
      signal: AbortSignal.timeout(timeoutMilliseconds),
    });
  } catch (error) {
    if (
      error instanceof DOMException &&
      (error.name === "TimeoutError" || error.name === "AbortError")
    ) {
      throw new Error("receipt_ocr_timeout");
    }
    throw new Error("receipt_ocr_unavailable");
  }
  if (!response.ok) {
    throw new Error(`receipt_ocr_http_${response.status}`);
  }

  let payload: {
    OCRExitCode?: unknown;
    IsErroredOnProcessing?: unknown;
    ParsedResults?: Array<{ ParsedText?: unknown }>;
  };
  try {
    payload = await response.json();
  } catch {
    throw new Error("receipt_ocr_invalid_response");
  }
  if (
    !payload || typeof payload !== "object" ||
    (payload.OCRExitCode !== 1 && payload.OCRExitCode !== 2) ||
    payload.IsErroredOnProcessing !== false ||
    !Array.isArray(payload.ParsedResults) ||
    !payload.ParsedResults[0] ||
    typeof payload.ParsedResults[0].ParsedText !== "string"
  ) {
    throw new Error("receipt_ocr_provider_error");
  }
  return parseReceiptText(
    payload.ParsedResults[0].ParsedText,
    null,
    image.width,
    image.height,
  );
}

export function classifyReceipt({
  result,
  submittedReference,
  submittedDate,
  submittedTime,
  expectedAmountCentavos,
  validImage = true,
}: {
  result: ReceiptOcrResult;
  submittedReference: string;
  submittedDate: string;
  submittedTime: string;
  expectedAmountCentavos: number;
  validImage?: boolean;
}): ReceiptClassification {
  const enteredReference = normalizeReference(submittedReference);
  const ocrReference = result.referenceNumber;
  const referenceMatch = ocrReference !== null &&
    normalizeReference(ocrReference) === enteredReference;
  const dateMatch = result.transactionDate === submittedDate;
  const timeMatch = normalizeTime(result.transactionTime) !== null &&
    normalizeTime(result.transactionTime) === normalizeTime(submittedTime);
  const amountMatch = result.amountCentavos === expectedAmountCentavos;
  const checks: ReceiptChecks = {
    validImage,
    isGcashReceipt: result.isGcashReceipt,
    imageReadable: (result.confidence === null || result.confidence >= 0.75) &&
      (result.imageWidth ?? 0) >= 300 &&
      (result.imageHeight ?? 0) >= 300,
    referenceMatch,
    amountMatch,
    dateMatch,
    timeMatch,
    duplicateReference: false,
  };
  const reject = (
    errorCode: string,
    reason: string,
  ): ReceiptClassification => ({
    status: "rejected",
    reason,
    errorCode,
    checks,
  });
  if (!validImage) {
    return reject(
      "not_a_receipt",
      notGcashReceiptMessage,
    );
  }
  if (
    result.providerIdentification === "other" ||
    result.providerIdentification === "unknown"
  ) {
    return reject(
      "not_a_receipt",
      notGcashReceiptMessage,
    );
  }
  if (
    !result.hasTransactionMarkers &&
    result.providerIdentification === "ambiguous"
  ) {
    return reject(
      "receipt_unreadable",
      unreadableReceiptMessage,
    );
  }
  if (!result.hasTransactionMarkers) {
    return reject(
      "receipt_unreadable",
      unreadableReceiptMessage,
    );
  }
  if (
    (result.imageWidth ?? 0) < 300 ||
    (result.imageHeight ?? 0) < 300
  ) {
    return reject(
      "receipt_unreadable",
      unreadableReceiptMessage,
    );
  }
  if (result.confidence !== null && result.confidence < 0.75) {
    return reject(
      "receipt_unreadable",
      unreadableReceiptMessage,
    );
  }
  if (!/^\d{13}$/.test(enteredReference)) {
    return reject(
      "reference_invalid",
      "Your reference number must contain exactly 13 digits in the format 0000 000 000000.",
    );
  }
  if (!ocrReference) {
    return reject("receipt_unreadable", unreadableReceiptMessage);
  }
  if (!referenceMatch) {
    return reject(
      "reference_mismatch",
      `The reference number you entered (${
        formatReference(enteredReference)
      }) does not match the reference found on the receipt (${
        formatReference(ocrReference)
      }). Please check your receipt and correct it.`,
    );
  }
  if (
    !result.transactionDate ||
    normalizeTime(result.transactionTime) === null ||
    result.amountCentavos === null ||
    result.transactionStatus === "unknown"
  ) {
    return reject("receipt_unreadable", unreadableReceiptMessage);
  }
  if (result.transactionStatus !== "successful") {
    return reject(
      "transaction_not_successful",
      "The GCash receipt does not show a successful transaction.",
    );
  }
  const discrepancy = !dateMatch
    ? ["payment_date_mismatch", "The transaction date differs."]
    : !timeMatch
    ? [
      "payment_time_mismatch",
      "The transaction time differs or is unreadable.",
    ]
    : !amountMatch
    ? ["wrong_payment_amount", "The transaction amount differs from the plan."]
    : null;
  if (discrepancy) {
    return {
      status: "manual_review",
      reason: discrepancy[1],
      errorCode: discrepancy[0],
      checks,
    };
  }
  if (result.providerIdentification === "ambiguous") {
    return {
      status: "manual_review",
      reason:
        "The OCR could not confidently identify the GCash provider text. Verify the provider and transaction manually.",
      errorCode: "receipt_provider_ambiguous",
      checks,
    };
  }
  if (result.confidence === null) {
    return {
      status: "manual_review",
      reason:
        "The OCR provider does not supply a confidence score. Verify the receipt manually.",
      errorCode: "ocr_confidence_unavailable",
      checks,
    };
  }
  return { status: "matched", reason: null, errorCode: null, checks };
}
