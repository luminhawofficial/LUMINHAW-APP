import {
  classifyReceipt,
  inspectReceiptImage,
  normalizeReference,
  parseReceiptText,
  readGcashReceipt,
} from "./receipt-ocr.ts";

const receiptText = [
  "GCash",
  "Payment successful",
  "Transaction Reference No. 1234 567 890123",
  "Amount PHP 49.00",
  "Date: 2026-11-06",
  "Time: 9:41 AM",
  "Recipient: LUMINHAW",
].join("\n");

Deno.test("receipt OCR extracts transaction fields from readable GCash text", () => {
  const result = parseReceiptText(receiptText, 0.96, 1080, 1920);
  if (
    result.referenceNumber !== "1234567890123" ||
    result.transactionDate !== "2026-11-06" ||
    result.transactionTime !== "9:41 AM" ||
    result.amountCentavos !== 4900 ||
    result.transactionStatus !== "successful" ||
    !result.isGcashReceipt
  ) {
    throw new Error("OCR should extract the expected GCash receipt fields.");
  }
});

Deno.test("matching 13-digit reference, date, and amount pass validation", () => {
  const result = parseReceiptText(receiptText, 0.96, 1080, 1920);
  const classification = classifyReceipt({
    result,
    submittedReference: "1234 567 890123",
    submittedDate: "2026-11-06",
    submittedTime: "09:41",
    expectedAmountCentavos: 4900,
  });
  if (classification.status !== "matched") {
    throw new Error("Matching receipt values should pass validation.");
  }
  if (
    !classification.checks.validImage ||
    !classification.checks.referenceMatch ||
    !classification.checks.amountMatch ||
    !classification.checks.dateMatch ||
    !classification.checks.timeMatch
  ) {
    throw new Error("A successful result must report all required checks.");
  }
});

Deno.test("reference mismatch is rejected with both spaced values", () => {
  const classification = classifyReceipt({
    result: parseReceiptText(receiptText, 0.96, 1080, 1920),
    submittedReference: "1234 567 890999",
    submittedDate: "2026-11-06",
    submittedTime: "09:41",
    expectedAmountCentavos: 4900,
  });
  if (
    classification.status !== "rejected" ||
    classification.errorCode !== "reference_mismatch" ||
    classification.reason !==
      "The reference number you entered (1234 567 890999) does not match the reference found on the receipt (1234 567 890123). Please check your receipt and correct it."
  ) {
    throw new Error("A reference mismatch must be rejected with both values.");
  }
});

Deno.test("reference labels and spaced or unspaced numbers are extracted", () => {
  for (
    const [label, expected] of [
      ["Ref. No:", "1234567890123"],
      ["Reference No.", "1234567890123"],
      ["Ref No:", "1234567890123"],
      ["Reference:", "1234567890123"],
    ]
  ) {
    const result = parseReceiptText(
      `GCash\nPayment successful\n${label} 1234 567 890123`,
      null,
      360,
      800,
    );
    if (result.referenceNumber !== expected) {
      throw new Error(`Could not extract reference labeled ${label}`);
    }
  }
  if (
    parseReceiptText(
      "GCash\nPayment successful\nReference No. 1234567890123",
      null,
      360,
      800,
    ).referenceNumber !== "1234567890123"
  ) {
    throw new Error("Could not extract the unspaced reference number.");
  }
});

Deno.test("receipt status recognizes successful-sent wording", () => {
  for (
    const phrase of ["sent successfully", "successfully sent", "payment sent"]
  ) {
    const result = parseReceiptText(
      receiptText.replace("Payment successful", phrase),
      null,
      360,
      800,
    );
    if (result.transactionStatus !== "successful") {
      throw new Error(`Could not recognize successful status: ${phrase}`);
    }
  }
});

Deno.test("300px mobile receipt images are readable with null OCR confidence", () => {
  for (const [width, height] of [[360, 800], [412, 915], [300, 300]]) {
    const result = parseReceiptText(receiptText, null, width, height);
    const classification = classifyReceipt({
      result,
      submittedReference: "1234567890123",
      submittedDate: "2026-11-06",
      submittedTime: "09:41",
      expectedAmountCentavos: 4900,
    });
    if (
      !classification.checks.imageReadable ||
      classification.status !== "manual_review"
    ) {
      throw new Error(`Valid ${width}x${height} receipt was rejected.`);
    }
  }
});

Deno.test("wrong amount is routed to manual review", () => {
  const classification = classifyReceipt({
    result: parseReceiptText(receiptText, 0.96, 1080, 1920),
    submittedReference: "1234567890123",
    submittedDate: "2026-11-06",
    submittedTime: "09:41",
    expectedAmountCentavos: 149900,
  });
  if (
    classification.status !== "manual_review" ||
    classification.errorCode !== "wrong_payment_amount"
  ) {
    throw new Error("An amount mismatch must be routed to review.");
  }
});

Deno.test("date and time differences are routed to manual review", () => {
  const dateMismatch = classifyReceipt({
    result: parseReceiptText(receiptText, 0.96, 1080, 1920),
    submittedReference: "1234567890123",
    submittedDate: "2026-11-05",
    submittedTime: "09:41",
    expectedAmountCentavos: 4900,
  });
  const timeMismatch = classifyReceipt({
    result: parseReceiptText(receiptText, 0.96, 1080, 1920),
    submittedReference: "1234567890123",
    submittedDate: "2026-11-06",
    submittedTime: "09:42",
    expectedAmountCentavos: 4900,
  });
  if (
    dateMismatch.status !== "manual_review" ||
    dateMismatch.errorCode !== "payment_date_mismatch" ||
    timeMismatch.status !== "manual_review" ||
    timeMismatch.errorCode !== "payment_time_mismatch"
  ) {
    throw new Error("Date or time differences must be routed to review.");
  }
});

Deno.test("unrelated image text is rejected as not a GCash receipt", () => {
  const result = parseReceiptText(
    "A green plant in a garden",
    0.99,
    1080,
    1920,
  );
  const classification = classifyReceipt({
    result,
    submittedReference: "1234567890123",
    submittedDate: "2026-11-06",
    submittedTime: "09:41",
    expectedAmountCentavos: 4900,
  });
  if (
    classification.status !== "rejected" ||
    classification.errorCode !== "not_a_receipt" ||
    classification.reason !==
      "The uploaded image does not appear to be a GCash receipt. Please upload or take a clear picture of your official GCash receipt."
  ) {
    throw new Error(
      "Unrelated image text must be rejected as a non-receipt.",
    );
  }
});

Deno.test("other wallet receipt is rejected as not GCash", () => {
  const result = parseReceiptText(
    "Maya payment successful\nReference No. 1234567890123\nPHP 49.00\n2026-11-06",
    0.99,
    1080,
    1920,
  );
  const classification = classifyReceipt({
    result,
    submittedReference: "1234567890123",
    submittedDate: "2026-11-06",
    submittedTime: "09:41",
    expectedAmountCentavos: 4900,
  });
  if (
    classification.errorCode !== "not_a_receipt" ||
    classification.reason !==
      "The uploaded image does not appear to be a GCash receipt. Please upload or take a clear picture of your official GCash receipt."
  ) {
    throw new Error("A non-GCash wallet receipt must be rejected.");
  }
});

Deno.test("OCR-like GCash text is sent to manual review, never auto-matched", () => {
  const result = parseReceiptText(
    receiptText.replace("GCash", "GCa5h"),
    0.99,
    1080,
    1920,
  );
  const classification = classifyReceipt({
    result,
    submittedReference: "1234567890123",
    submittedDate: "2026-11-06",
    submittedTime: "09:41",
    expectedAmountCentavos: 4900,
  });
  if (
    result.providerIdentification !== "ambiguous" ||
    result.isGcashReceipt ||
    classification.status !== "manual_review" ||
    classification.errorCode !== "receipt_provider_ambiguous"
  ) {
    throw new Error(
      "A likely GCash OCR misread must be manually verified, not auto-matched.",
    );
  }
});

Deno.test("missing provider identification is rejected, not proven by a reference", () => {
  const result = parseReceiptText(
    receiptText.replace("GCash\n", ""),
    0.99,
    1080,
    1920,
  );
  const classification = classifyReceipt({
    result,
    submittedReference: "1234567890123",
    submittedDate: "2026-11-06",
    submittedTime: "09:41",
    expectedAmountCentavos: 4900,
  });
  if (
    result.referenceNumber !== "1234567890123" ||
    result.providerIdentification !== "unknown" ||
    classification.status !== "rejected" ||
    classification.errorCode !== "not_a_receipt"
  ) {
    throw new Error(
      "Transaction details without a provider label must be rejected.",
    );
  }
});

Deno.test("incomplete transaction details are rejected as unreadable", () => {
  const result = parseReceiptText(
    "GCash\nPayment successful\nReference No. 1234567890123",
    null,
    1080,
    1920,
  );
  const classification = classifyReceipt({
    result,
    submittedReference: "1234567890123",
    submittedDate: "2026-11-06",
    submittedTime: "09:41",
    expectedAmountCentavos: 4900,
  });
  if (
    classification.status !== "rejected" ||
    classification.errorCode !== "receipt_unreadable"
  ) {
    throw new Error(
      "Missing required transaction fields must be unreadable.",
    );
  }
});

Deno.test("missing transaction time is rejected as unreadable", () => {
  const result = parseReceiptText(
    receiptText.replace("Time: 9:41 AM\n", ""),
    null,
    1080,
    1920,
  );
  const classification = classifyReceipt({
    result,
    submittedReference: "1234567890123",
    submittedDate: "2026-11-06",
    submittedTime: "09:41",
    expectedAmountCentavos: 4900,
  });
  if (
    classification.status !== "rejected" ||
    classification.errorCode !== "receipt_unreadable"
  ) {
    throw new Error("A receipt without transaction time must be inconclusive.");
  }
});

Deno.test("failed transactions cannot pass", () => {
  const result = parseReceiptText(
    receiptText.replace("Payment successful", "Payment failed"),
    0.96,
    1080,
    1920,
  );
  const classification = classifyReceipt({
    result,
    submittedReference: "1234567890123",
    submittedDate: "2026-11-06",
    submittedTime: "09:41",
    expectedAmountCentavos: 4900,
  });
  if (classification.errorCode !== "transaction_not_successful") {
    throw new Error("Unsuccessful transactions must be rejected.");
  }
});

Deno.test("low-confidence and incomplete receipts fail closed", () => {
  const blurry = classifyReceipt({
    result: parseReceiptText(receiptText, 0.4, 1080, 1920),
    submittedReference: "1234567890123",
    submittedDate: "2026-11-06",
    submittedTime: "09:41",
    expectedAmountCentavos: 4900,
  });
  const unreadable = classifyReceipt({
    result: parseReceiptText(receiptText, 0.7, 1080, 1920),
    submittedReference: "1234567890123",
    submittedDate: "2026-11-06",
    submittedTime: "09:41",
    expectedAmountCentavos: 4900,
  });
  if (
    blurry.errorCode !== "receipt_unreadable" ||
    unreadable.errorCode !== "receipt_unreadable" ||
    blurry.reason !==
      "The receipt is blurry or the transaction details cannot be read clearly. Please take a clear, well-lit photo of the receipt, or send it to luminhawofficial@gmail.com for assistance."
  ) {
    throw new Error("Low OCR confidence must fail closed with clear errors.");
  }
});

Deno.test("reference format requires exactly thirteen digits", () => {
  if (normalizeReference("1234 567 890123") !== "1234567890123") {
    throw new Error("Reference formatting should only remove spaces.");
  }
  const classification = classifyReceipt({
    result: parseReceiptText(receiptText, 0.96, 1080, 1920),
    submittedReference: "123456789012",
    submittedDate: "2026-11-06",
    submittedTime: "09:41",
    expectedAmountCentavos: 4900,
  });
  if (classification.errorCode !== "reference_invalid") {
    throw new Error("Non-13-digit references must be rejected.");
  }
});

Deno.test("image signatures and structural bounds are checked", () => {
  const png = new Uint8Array(8 + 25 + 13 + 12);
  png.set([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  const view = new DataView(png.buffer);
  view.setUint32(8, 13);
  png.set([0x49, 0x48, 0x44, 0x52], 12);
  view.setUint32(16, 1080);
  view.setUint32(20, 1920);
  view.setUint32(33, 1);
  png.set([0x49, 0x44, 0x41, 0x54], 37);
  png[41] = 0;
  view.setUint32(42, 0);
  view.setUint32(46, 0);
  png.set([0x49, 0x45, 0x4e, 0x44], 50);
  const valid = inspectReceiptImage(png);
  if (!valid.valid || valid.mimeType !== "image/png") {
    throw new Error("A structurally valid PNG should be recognized.");
  }
  const truncated = inspectReceiptImage(png.slice(0, -1));
  if (truncated.valid) {
    throw new Error("A truncated PNG must be rejected.");
  }
  if (inspectReceiptImage(new Uint8Array([0x89, 0x50, 0x4e, 0x47])).valid) {
    throw new Error("A short signature alone must not count as an image.");
  }
});

Deno.test("OCR.space sends multipart image data and parses a mocked response", async () => {
  const png = new Uint8Array(8 + 25 + 13 + 12);
  png.set([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  const view = new DataView(png.buffer);
  view.setUint32(8, 13);
  png.set([0x49, 0x48, 0x44, 0x52], 12);
  view.setUint32(16, 1080);
  view.setUint32(20, 1920);
  view.setUint32(33, 1);
  png.set([0x49, 0x44, 0x41, 0x54], 37);
  png[41] = 0;
  view.setUint32(42, 0);
  view.setUint32(46, 0);
  png.set([0x49, 0x45, 0x4e, 0x44], 50);

  let callCount = 0;
  const result = await readGcashReceipt(
    png,
    "test-ocr-space-key",
    async (input, init) => {
      callCount++;
      const request = new Request(input, init);
      const url = new URL(request.url);
      const payload = await request.formData();
      const uploadedImage = payload.get("file");
      if (
        url.origin !== "https://api.ocr.space" ||
        url.pathname !== "/parse/image" ||
        request.headers.get("apikey") !== "test-ocr-space-key" ||
        request.method !== "POST" ||
        !request.headers.get("content-type")?.startsWith(
          "multipart/form-data; boundary=",
        ) ||
        payload.get("OCREngine") !== "2" ||
        !(uploadedImage instanceof File) ||
        uploadedImage.type !== "image/png" ||
        uploadedImage.name !== "receipt.png" ||
        new Uint8Array(await uploadedImage.arrayBuffer()).some(
          (byte, index) => byte !== png[index],
        )
      ) {
        throw new Error("The OCR.space request must contain the test image.");
      }
      return Response.json({
        OCRExitCode: 1,
        IsErroredOnProcessing: false,
        ParsedResults: [{ ParsedText: receiptText }],
      });
    },
  );
  if (
    callCount !== 1 ||
    result.referenceNumber !== "1234567890123" ||
    result.amountCentavos !== 4900 ||
    result.transactionDate !== "2026-11-06" ||
    result.transactionTime !== "9:41 AM" ||
    result.confidence !== null ||
    result.imageWidth !== 1080 ||
    result.imageHeight !== 1920
  ) {
    throw new Error("The mocked OCR.space response should parse as a receipt.");
  }
  const classification = classifyReceipt({
    result,
    submittedReference: "1234567890123",
    submittedDate: "2026-11-06",
    submittedTime: "09:41",
    expectedAmountCentavos: 4900,
  });
  if (
    classification.status !== "manual_review" ||
    classification.errorCode !== "ocr_confidence_unavailable" ||
    !classification.checks.imageReadable ||
    !classification.checks.timeMatch
  ) {
    throw new Error(
      "OCR.space receipts must keep time matching and require manual review.",
    );
  }
});

Deno.test("OCR.space HTTP errors fail without reporting OCR results", async () => {
  const png = new Uint8Array(8 + 25 + 13 + 12);
  png.set([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  const view = new DataView(png.buffer);
  view.setUint32(8, 13);
  png.set([0x49, 0x48, 0x44, 0x52], 12);
  view.setUint32(16, 10);
  view.setUint32(20, 10);
  view.setUint32(33, 1);
  png.set([0x49, 0x44, 0x41, 0x54], 37);
  view.setUint32(46, 0);
  png.set([0x49, 0x45, 0x4e, 0x44], 50);

  let rejected = false;
  try {
    await readGcashReceipt(
      png,
      "test-ocr-space-key",
      async () => new Response("unavailable", { status: 503 }),
    );
  } catch (error) {
    rejected = error instanceof Error &&
      error.message === "receipt_ocr_http_503";
  }
  if (!rejected) {
    throw new Error("An OCR.space HTTP error must not produce OCR results.");
  }
});

Deno.test("OCR.space timeout, malformed JSON, and provider errors fail closed", async () => {
  const png = new Uint8Array(8 + 25 + 13 + 12);
  png.set([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  const view = new DataView(png.buffer);
  view.setUint32(8, 13);
  png.set([0x49, 0x48, 0x44, 0x52], 12);
  view.setUint32(16, 10);
  view.setUint32(20, 10);
  view.setUint32(33, 1);
  png.set([0x49, 0x44, 0x41, 0x54], 37);
  view.setUint32(46, 0);
  png.set([0x49, 0x45, 0x4e, 0x44], 50);

  for (
    const [fetcher, expectedError] of [
      [
        async () => {
          throw new DOMException("Request timed out", "TimeoutError");
        },
        "receipt_ocr_timeout",
      ],
      [
        async () => new Response("{invalid"),
        "receipt_ocr_invalid_response",
      ],
      [
        async () =>
          Response.json({
            OCRExitCode: 3,
            IsErroredOnProcessing: true,
            ParsedResults: [],
          }),
        "receipt_ocr_provider_error",
      ],
    ] as const
  ) {
    try {
      await readGcashReceipt(png, "test-ocr-space-key", fetcher);
      throw new Error("Invalid OCR.space results must not be accepted.");
    } catch (error) {
      if (!(error instanceof Error) || error.message !== expectedError) {
        throw error;
      }
    }
  }
});
