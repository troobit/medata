/**
 * Azure Blob Storage implementation of IImageRepository.
 * Per design section 3.4 and D-DES-016.
 */
import { ContainerClient } from '@azure/storage-blob';
import type { IImageRepository, ImageFolder } from './image-repository.js';
import { BLOB_SAS_URL } from '$env/static/private';

const CONTAINER_NAME = 'images';

/**
 * Azure Blob Storage implementation of the image repository.
 * Per design section 4.3: images/meals/ and images/labels/ folders.
 */
export class BlobImageRepository implements IImageRepository {
	private containerClient: ContainerClient | null = null;
	private initialised = false;
	private sasUrl: string;

	constructor(sasUrl?: string) {
		const url = sasUrl ?? BLOB_SAS_URL;
		if (!url) {
			throw new Error('BLOB_SAS_URL environment variable is not set');
		}
		this.sasUrl = url;
	}

	/**
	 * Ensure container client is initialized.
	 */
	private ensureInitialised(): ContainerClient {
		if (this.initialised && this.containerClient) {
			return this.containerClient;
		}

		// Create container client from SAS URL
		// The SAS URL already includes the container and auth
		this.containerClient = new ContainerClient(this.sasUrl);
		this.initialised = true;

		return this.containerClient;
	}

	async upload(image: Buffer, folder: ImageFolder, filename: string): Promise<string> {
		const containerClient = this.ensureInitialised();

		// Build the blob path: folder/filename (e.g., 'meals/uuid.jpg')
		const blobPath = `${folder}/${filename}`;

		const blockBlobClient = containerClient.getBlockBlobClient(blobPath);

		// Determine content type from filename extension
		const contentType = this.getContentType(filename);

		// Upload the image
		await blockBlobClient.uploadData(image, {
			blobHTTPHeaders: {
				blobContentType: contentType
			}
		});

		// Return the public URL (without SAS token for storage)
		// The SAS URL includes query params, so we need to extract just the base URL
		const baseUrl = this.sasUrl.split('?')[0];
		return `${baseUrl}/${blobPath}`;
	}

	async delete(url: string): Promise<void> {
		const containerClient = this.ensureInitialised();

		// Extract blob path from URL
		const blobPath = this.extractBlobPath(url);
		if (!blobPath) {
			throw new Error(`Invalid blob URL: ${url}`);
		}

		const blockBlobClient = containerClient.getBlockBlobClient(blobPath);

		// Delete the blob (ignore if not exists)
		await blockBlobClient.deleteIfExists();
	}

	/**
	 * Get content type from filename extension.
	 */
	private getContentType(filename: string): string {
		const ext = filename.split('.').pop()?.toLowerCase();
		switch (ext) {
			case 'jpg':
			case 'jpeg':
				return 'image/jpeg';
			case 'png':
				return 'image/png';
			default:
				return 'application/octet-stream';
		}
	}

	/**
	 * Extract blob path from a full URL.
	 * URL format: https://{account}.blob.core.windows.net/{container}/{folder}/{filename}
	 */
	private extractBlobPath(url: string): string | null {
		try {
			const urlObj = new URL(url);
			const pathParts = urlObj.pathname.split('/').filter(Boolean);

			// Remove container name from path to get blob path
			if (pathParts.length >= 2 && pathParts[0] === CONTAINER_NAME) {
				return pathParts.slice(1).join('/');
			}

			// If container isn't in path, return the full path
			return pathParts.join('/');
		} catch {
			return null;
		}
	}
}

/**
 * Singleton instance for the image repository.
 */
let imageRepository: BlobImageRepository | null = null;

/**
 * Get the image repository instance.
 * Creates a new instance if one doesn't exist.
 */
export function getImageRepository(): IImageRepository {
	if (!imageRepository) {
		imageRepository = new BlobImageRepository();
	}
	return imageRepository;
}
