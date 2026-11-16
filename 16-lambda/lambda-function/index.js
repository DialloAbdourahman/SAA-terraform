const {
  S3Client,
  GetObjectCommand,
  PutObjectCommand,
} = require("@aws-sdk/client-s3");
const { SQSClient, DeleteMessageCommand } = require("@aws-sdk/client-sqs");
const sharp = require("sharp");

const s3 = new S3Client({});
const sqs = new SQSClient({});

const ENVIRONMENT = process.env.ENVIRONMENT || "development";
const LOG_LEVEL = process.env.LOG_LEVEL || "info";
const TARGET_WIDTH = parseInt(process.env.TARGET_WIDTH || "300", 10);
const TARGET_HEIGHT = parseInt(process.env.TARGET_HEIGHT || "300", 10);
const OUTPUT_PREFIX = process.env.OUTPUT_PREFIX || "resized/";
const QUEUE_URL = process.env.QUEUE_URL;

const IMAGE_EXTENSIONS = new Set([
  ".jpg",
  ".jpeg",
  ".png",
  ".gif",
  ".webp",
  ".bmp",
  ".tiff",
  ".tif",
  ".avif",
]);

function isImageKey(key) {
  const ext = key.slice(key.lastIndexOf(".")).toLowerCase();
  return IMAGE_EXTENSIONS.has(ext);
}

const LOG_LEVELS = { debug: 10, info: 20, warn: 30, error: 40 };
const currentLevel = LOG_LEVELS[LOG_LEVEL] ?? LOG_LEVELS.info;

function log(level, message, extra) {
  if (LOG_LEVELS[level] < currentLevel) return;
  console.log(
    JSON.stringify({
      timestamp: new Date().toISOString(),
      level,
      environment: ENVIRONMENT,
      message,
      ...extra,
    }),
  );
}

async function streamToBuffer(stream) {
  const chunks = [];
  for await (const chunk of stream) {
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}

function getOutputKey(inputKey) {
  const fileName = inputKey.split("/").pop();
  const nameWithoutExt = fileName.replace(/\.[^.]+$/, "");
  return `${OUTPUT_PREFIX}${nameWithoutExt}-${TARGET_WIDTH}x${TARGET_HEIGHT}.jpg`;
}

async function processS3Record(s3Record) {
  const bucket = s3Record.s3.bucket.name;
  const key = decodeURIComponent(s3Record.s3.object.key.replace(/\+/g, " "));

  if (!isImageKey(key)) {
    log("info", "Skipping non-image object", { bucket, key });
    return;
  }

  if (key.startsWith(OUTPUT_PREFIX)) {
    log("info", "Skipping already-resized object", { bucket, key });
    return;
  }

  log("info", "Processing S3 object", { bucket, key });

  const getResponse = await s3.send(
    new GetObjectCommand({
      Bucket: bucket,
      Key: key,
    }),
  );

  if (
    getResponse.ContentType &&
    !getResponse.ContentType.startsWith("image/")
  ) {
    log("info", "Skipping non-image content type", {
      bucket,
      key,
      contentType: getResponse.ContentType,
    });
    return;
  }

  const imageBuffer = await streamToBuffer(getResponse.Body);

  const resizedBuffer = await sharp(imageBuffer)
    .resize(TARGET_WIDTH, TARGET_HEIGHT, {
      fit: "inside",
      withoutEnlargement: true,
    })
    .jpeg({ quality: 80 })
    .toBuffer();

  const outputKey = getOutputKey(key);

  await s3.send(
    new PutObjectCommand({
      Bucket: bucket,
      Key: outputKey,
      Body: resizedBuffer,
      ContentType: "image/jpeg",
    }),
  );

  log("info", "Resized image uploaded", {
    sourceKey: key,
    outputKey,
    originalSize: imageBuffer.length,
    resizedSize: resizedBuffer.length,
  });
}

const handler = async (event) => {
  log("info", "Lambda invoked", { recordCount: event.Records?.length ?? 0 });

  for (const record of event.Records || []) {
    const body = JSON.parse(record.body);

    // S3 event notification wrapped in an SQS message
    const s3Records = body.Records || [];

    for (const s3Record of s3Records) {
      if (s3Record.eventSource !== "aws:s3" && !s3Record.s3) continue;
      await processS3Record(s3Record);
    }

    // Delete the message from the queue after handling
    await sqs.send(
      new DeleteMessageCommand({
        QueueUrl: QUEUE_URL,
        ReceiptHandle: record.receiptHandle,
      }),
    );

    log("info", "Message deleted from queue", { messageId: record.messageId });
  }

  return {
    statusCode: 200,
    body: JSON.stringify({ message: "Processing complete" }),
  };
};

module.exports = { handler };
