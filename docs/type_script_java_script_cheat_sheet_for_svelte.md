# TypeScript / JavaScript Cheat Sheet for Svelte Development

This document is a **syntax and paradigm reference** for engineers new to JavaScript, TypeScript, and Svelte, but experienced with infrastructure, CI/CD, and declarative systems. It is intended for **reading existing codebases**, understanding small functions quickly, and recognising common patterns and best practices.

---

## 1. JavaScript vs TypeScript (in Svelte)

### JavaScript (JS)
- Dynamically typed
- Runs in the browser (or Node.js)
- No compile-time guarantees

### TypeScript (TS)
- Superset of JavaScript
- Adds **static typing**
- Compiles to JavaScript
- Commonly used in Svelte via `<script lang="ts">`

**Mental model:**  
TypeScript is to JavaScript what Terraform `type = object({ ... })` is to untyped JSON.

---

## 2. Modules and File Structure

```ts
// SomeService.ts
export class SomeService {
	constructor() {}
}
```

```svelte
<script lang="ts">
	import { SomeService } from './SomeService';
</script>
```

- Each file is a module
- `export` makes symbols visible to other files
- `import` consumes them

---

## 3. Classes and `constructor()`

```ts
class ImageService {
	apiKey: string;

	constructor(apiKey: string) {
		this.apiKey = apiKey;
	}
}
```

### What `constructor()` means
- Executed when the class is instantiated
- Used to initialise state or inject dependencies

```ts
const service = new ImageService('abc123');
```

**Infrastructure analogy:**  
`constructor()` is equivalent to wiring Terraform module inputs into locals/resources.

---

## 4. Function Syntax Variants

### Standard function
```ts
function add(a: number, b: number): number {
	return a + b;
}
```

### Arrow function
```ts
const add = (a: number, b: number): number => a + b;
```

### Async function
```ts
async function fetchData(): Promise<Data> {
	...
}
```

Arrow functions are common in callbacks, stores, and Svelte components.

---

## 5. Promises (Core Concept)

### What a Promise Is
A `Promise<T>` represents a value that:
- Does not exist yet
- Will exist in the future
- May fail

```ts
Promise<T>
```

**Mental model:**
- Terraform `apply`
- A CI job step that completes later

### Example
```ts
function getUser(): Promise<User> {
	return fetch('/api/user').then(r => r.json());
}
```

This function does **not** return `User`, it returns a **Promise of User**.

---

## 6. `async` / `await`

### Without `await`
```ts
getUser().then(user => {
	console.log(user);
});
```

### With `await`
```ts
const user = await getUser();
console.log(user);
```

Rules:
- `await` only works inside `async` functions
- Any `async` function always returns a `Promise<T>`

---

## 7. Reading Function Signatures

```ts
recognise(
	image: Blob,
	labelContext?: LabelContext
): Promise<FoodRecognitionResult>;
```

### Breakdown
- `image: Blob` → required argument
- `labelContext?: LabelContext` → optional argument (`undefined` allowed)
- Returns a `Promise<FoodRecognitionResult>`

Meaning:
> “Call this with an image. At some point in the future, you will receive a recognition result.”

Usage:
```ts
const result = await recognise(image);
```

---

## 8. Web-Specific Types

### `Blob`
- Binary large object
- Represents files, images, uploads
- Common in browser APIs

### `ArrayBuffer`
- Low-level binary buffer

### `Uint8Array`
- Typed view into binary data (byte-level access)

---

## 9. Worked Example: `blobToBase64`

```ts
async function blobToBase64(blob: Blob): Promise<string> {
	const buffer = await blob.arrayBuffer();
	const bytes = new Uint8Array(buffer);
	let binary = '';
	for (let i = 0; i < bytes.length; i++) {
		binary += String.fromCharCode(bytes[i]!);
	}
	return btoa(binary);
}
```

### Step-by-step

1. Convert the `Blob` into raw binary data
```ts
const buffer = await blob.arrayBuffer();
```

2. Create a byte-level view
```ts
const bytes = new Uint8Array(buffer);
```

3. Convert bytes into a binary string
```ts
binary += String.fromCharCode(bytes[i]!);
```

- `!` is a **non-null assertion** in TypeScript
- It tells the compiler the value is safe

4. Base64 encode
```ts
return btoa(binary);
```

### Result
- A Base64 string suitable for JSON payloads, inline images, or APIs that reject binary input

---

## 10. Interfaces (Type Contracts)

```ts
interface FoodRecognitionResult {
	labels: string[];
	confidence: number;
}
```

- Compile-time only
- Enforces object shape
- No runtime presence

**Equivalent to:**
- Terraform object types
- API schema contracts

---

## 11. Optional Properties

```ts
interface Config {
	timeout?: number;
}
```

- `?` indicates optional
- Value may be `undefined`

---

## 12. Repository Pattern

```ts
class UserRepository {
	async getUser(id: string): Promise<User> {
		...
	}
}
```

Purpose:
- Isolate data access
- Hide API or storage details
- Improve testability

**Infrastructure analogy:** wrapper modules hiding provider complexity.

---

## 13. Svelte-Specific Concepts

### Reactive statements
```ts
$: total = price * quantity;
```

- Automatically re-runs when dependencies change

### Stores
```ts
import { writable } from 'svelte/store';

export const user = writable<User | null>(null);
```

- Reactive state containers
- Used for cross-component state

---

## 14. Common Idioms

### Guard clauses
```ts
if (!value) return;
```

### Destructuring
```ts
const { id, name } = user;
```

### Functional iteration
```ts
items.map(x => x.id);
```

---

## 15. Reading Strategy for Existing Code

When analysing a function:
1. Identify the **return type**
2. Check if it is `async`
3. Trace where the Promise resolves
4. Look for side effects (API calls, stores, DOM)

If the return type is `Promise<T>`, the value does **not** exist yet.

---

This document is intended as a **starting reference**, prioritising comprehension of real-world code over language completeness.

