import { json } from "@sveltejs/kit";
import { createRecognitionService } from "$lib/services/recognition.js";

export async function GET() {
  try {
    const service = createRecognitionService();
    return json({
      configured: service.isReady(),
      mockMode: service.getBackendType() === "mock",
    });
  } catch {
    return json({ configured: false, mockMode: false });
  }
}
