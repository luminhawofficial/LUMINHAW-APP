type ImageInspection = {
  valid: boolean;
  mimeType: "image/jpeg" | "image/png" | null;
};

function uint32be(bytes: Uint8Array, offset: number): number {
  return new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength)
    .getUint32(offset, false);
}

function uint16be(bytes: Uint8Array, offset: number): number {
  return new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength)
    .getUint16(offset, false);
}

// Confirms the uploaded bytes are a bounded JPEG or PNG. It does not inspect
// image contents or extract transaction details.
export function inspectReceiptImage(bytes: Uint8Array): ImageInspection {
  if (bytes.length < 24 || bytes.length > 5 * 1024 * 1024) {
    return { valid: false, mimeType: null };
  }
  const png = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  if (png.every((byte, index) => bytes[index] === byte)) {
    if (String.fromCharCode(...bytes.slice(12, 16)) !== "IHDR" || uint32be(bytes, 8) !== 13) {
      return { valid: false, mimeType: null };
    }
    const width = uint32be(bytes, 16);
    const height = uint32be(bytes, 20);
    let offset = 8;
    let foundImageData = false;
    let foundEnd = false;
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
    };
  }
  if (bytes[0] !== 0xff || bytes[1] !== 0xd8) {
    return { valid: false, mimeType: null };
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
    if (marker === 0xda) { foundScan = true; break; }
    if (marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) continue;
    if (offset + 2 > bytes.length) break;
    const segmentLength = uint16be(bytes, offset);
    if (segmentLength < 2 || offset + segmentLength > bytes.length) break;
    if ((marker >= 0xc0 && marker <= 0xc3) || (marker >= 0xc5 && marker <= 0xc7) ||
      (marker >= 0xc9 && marker <= 0xcb) || (marker >= 0xcd && marker <= 0xcf)) {
      if (segmentLength < 7) break;
      height = uint16be(bytes, offset + 3);
      width = uint16be(bytes, offset + 5);
    }
    offset += segmentLength;
  }
  const valid = bytes.at(-2) === 0xff && bytes.at(-1) === 0xd9 && foundScan &&
    width !== null && height !== null && width > 0 && height > 0 &&
    width <= 12_000 && height <= 12_000 && width * height <= 50_000_000;
  return { valid, mimeType: "image/jpeg" };
}

export function manilaDateString(now: Date = new Date()): string {
  return new Date(now.getTime() + 8 * 60 * 60 * 1000).toISOString().slice(0, 10);
}
