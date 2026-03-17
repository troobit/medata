/**
 * Image repository interface.
 * Per design section 3.3.
 * Req 4.3, 11.2
 */

/**
 * Folder destinations for images.
 * Per design section 4.3.
 */
export type ImageFolder = 'meals' | 'labels';

/**
 * Interface for image storage.
 * Abstracts blob storage operations.
 */
export interface IImageRepository {
	/**
	 * Upload an image to blob storage.
	 * Req 4.3: Store the original image in blob storage when a photo is used.
	 * Req 11.2: Use secure best practice for image uploads.
	 *
	 * @param image - The image data as a Buffer
	 * @param folder - The folder to store in ('meals' or 'labels')
	 * @param filename - The filename to use (typically UUID.ext)
	 * @returns The public URL of the uploaded image
	 */
	upload(image: Buffer, folder: ImageFolder, filename: string): Promise<string>;

	/**
	 * Delete an image from blob storage.
	 *
	 * @param url - The full URL of the image to delete
	 */
	delete(url: string): Promise<void>;
}
