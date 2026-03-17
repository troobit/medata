/**
 * POST /api/images/upload endpoint
 * Per design section 3.4
 * Accept multipart/form-data with image file
 * Return imageUrl
 * Req 11.5: Credentials server-side only
 */
import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getImageRepository, type ImageFolder } from '$lib/repositories/index.js';

// Max image size: 10MB per design
const MAX_IMAGE_SIZE = 10 * 1024 * 1024;

// Allowed MIME types per Req 1.2
const ALLOWED_MIME_TYPES = ['image/jpeg', 'image/png'];

/**
 * Get file extension from MIME type.
 */
function getExtension(mimeType: string): string {
	switch (mimeType) {
		case 'image/jpeg':
			return 'jpg';
		case 'image/png':
			return 'png';
		default:
			return 'bin';
	}
}

export const POST: RequestHandler = async ({ request }) => {
	// Parse multipart form data
	let formData: FormData;
	try {
		formData = await request.formData();
	} catch {
		return error(400, {
			message: 'Invalid form data. Use multipart/form-data.'
		});
	}

	// Get the image file
	const imageFile = formData.get('image');
	if (!imageFile || !(imageFile instanceof File)) {
		return error(400, {
			message: 'No image file provided. Include an "image" field.'
		});
	}

	// Validate MIME type
	if (!ALLOWED_MIME_TYPES.includes(imageFile.type)) {
		return error(400, {
			message: 'Invalid image format. Use JPEG or PNG.'
		});
	}

	// Validate file size
	if (imageFile.size > MAX_IMAGE_SIZE) {
		return error(400, {
			message: 'Image too large. Maximum size is 10MB.'
		});
	}

	// Get folder (optional, defaults to 'meals')
	const folderParam = formData.get('folder');
	const folder: ImageFolder =
		folderParam === 'labels' || folderParam === 'meals' ? folderParam : 'meals';

	// Generate unique filename
	const extension = getExtension(imageFile.type);
	const filename = `${crypto.randomUUID()}.${extension}`;

	// Convert File to Buffer
	let imageBuffer: Buffer;
	try {
		const arrayBuffer = await imageFile.arrayBuffer();
		imageBuffer = Buffer.from(arrayBuffer);
	} catch {
		return error(400, {
			message: 'Failed to read image data.'
		});
	}

	// Upload to blob storage
	try {
		const imageRepository = getImageRepository();
		const imageUrl = await imageRepository.upload(imageBuffer, folder, filename);

		return json({
			data: {
				imageUrl
			}
		});
	} catch (e) {
		console.error('Image upload error:', e);
		return error(500, {
			message: 'Image upload failed. Try again.'
		});
	}
};
