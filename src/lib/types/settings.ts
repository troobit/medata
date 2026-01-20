import type { BSLUnit, InsulinType } from './events';

/**
 * AI provider options for food recognition
 */
export type AIProvider = 'openai' | 'gemini' | 'claude' | 'azure' | 'bedrock' | 'local';

/**
 * Azure OpenAI configuration
 */
export interface AzureConfig {
  apiKey?: string;
  endpoint?: string; // e.g., https://your-resource.openai.azure.com
  deploymentName?: string; // e.g., gpt-4o
  apiVersion?: string; // e.g., 2024-02-15-preview
}

/**
 * Amazon Bedrock configuration
 */
export interface BedrockConfig {
  accessKeyId?: string;
  secretAccessKey?: string;
  region?: string; // e.g., us-east-1
  modelId?: string; // e.g., anthropic.claude-3-sonnet-20240229-v1:0
}

/**
 * Local model configuration (Ollama, LM Studio, etc.)
 */
export interface LocalModelConfig {
  endpoint?: string; // e.g., http://localhost:11434/api
  modelName?: string; // e.g., llava, bakllava
  type?: 'ollama' | 'lmstudio' | 'openai-compatible';
}

/**
 * User preferences and settings
 */
export interface UserSettings {
  // AI Configuration
  aiProvider?: AIProvider;
  openaiApiKey?: string;
  geminiApiKey?: string;
  claudeApiKey?: string;

  // Azure OpenAI
  azureConfig?: AzureConfig;

  // Amazon Bedrock
  bedrockConfig?: BedrockConfig;

  // Local Models
  localModelConfig?: LocalModelConfig;

  // Defaults
  defaultInsulinType: InsulinType;
  defaultBSLUnit: BSLUnit;

  // Display
  darkMode: 'system' | 'light' | 'dark';

  // Data
  lastSyncTimestamp?: Date;
}

/**
 * Environment variable names for configuration
 */
export const ENV_VAR_NAMES = {
  // Direct API providers
  OPENAI_API_KEY: 'VITE_OPENAI_API_KEY',
  GEMINI_API_KEY: 'VITE_GEMINI_API_KEY',
  CLAUDE_API_KEY: 'VITE_CLAUDE_API_KEY',

  // Azure OpenAI
  AZURE_OPENAI_API_KEY: 'VITE_AZURE_OPENAI_API_KEY',
  AZURE_OPENAI_ENDPOINT: 'VITE_AZURE_OPENAI_ENDPOINT',
  AZURE_OPENAI_DEPLOYMENT: 'VITE_AZURE_OPENAI_DEPLOYMENT',
  AZURE_OPENAI_API_VERSION: 'VITE_AZURE_OPENAI_API_VERSION',

  // Amazon Bedrock
  AWS_ACCESS_KEY_ID: 'VITE_AWS_ACCESS_KEY_ID',
  AWS_SECRET_ACCESS_KEY: 'VITE_AWS_SECRET_ACCESS_KEY',
  AWS_REGION: 'VITE_AWS_REGION',
  BEDROCK_MODEL_ID: 'VITE_BEDROCK_MODEL_ID',

  // Local Models
  LOCAL_MODEL_ENDPOINT: 'VITE_LOCAL_MODEL_ENDPOINT',
  LOCAL_MODEL_NAME: 'VITE_LOCAL_MODEL_NAME',
  LOCAL_MODEL_TYPE: 'VITE_LOCAL_MODEL_TYPE',

  // Default provider
  AI_PROVIDER: 'VITE_AI_PROVIDER'
} as const;

/**
 * Default settings for new users
 */
export const DEFAULT_SETTINGS: UserSettings = {
  defaultInsulinType: 'bolus',
  defaultBSLUnit: 'mmol/L',
  darkMode: 'system'
};
