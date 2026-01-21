<script lang="ts">
  interface Props {
    type?: 'text' | 'email' | 'password' | 'tel' | 'url' | 'search' | 'number';
    value?: string;
    placeholder?: string;
    label?: string;
    id?: string;
    name?: string;
    required?: boolean;
    disabled?: boolean;
    error?: string;
    class?: string;
    oninput?: (event: Event & { currentTarget: HTMLInputElement }) => void;
    onblur?: (event: FocusEvent & { currentTarget: HTMLInputElement }) => void;
    onfocus?: (event: FocusEvent & { currentTarget: HTMLInputElement }) => void;
  }

  let {
    type = 'text',
    value = $bindable(''),
    placeholder,
    label,
    id,
    name,
    required = false,
    disabled = false,
    error,
    class: className = '',
    oninput,
    onblur,
    onfocus
  }: Props = $props();

  let isFocused = $state(false);

  function generateId(): string {
    if (typeof crypto !== 'undefined' && crypto.randomUUID) {
      return crypto.randomUUID();
    }
    return `input-${Math.random().toString(36).slice(2, 11)}`;
  }

  const generatedId = generateId();
  const inputId = $derived(id || name || generatedId);

  // Label floats when input is focused OR has a value
  const isFloating = $derived(isFocused || (value && value.length > 0));

  const baseClasses =
    'w-full px-4 py-3 text-base rounded-lg border transition-all duration-200 bg-gray-800 text-white disabled:opacity-50 disabled:cursor-not-allowed';

  const stateClasses = $derived(
    error
      ? 'border-red-500 focus:border-red-400 focus:ring-red-500/30'
      : 'border-gray-700 focus:border-brand-accent focus:ring-brand-accent/30'
  );

  const classes = $derived(
    [baseClasses, stateClasses, 'focus:outline-none focus:ring-2', className].join(' ')
  );

  function handleFocus(event: FocusEvent & { currentTarget: HTMLInputElement }) {
    isFocused = true;
    onfocus?.(event);
  }

  function handleBlur(event: FocusEvent & { currentTarget: HTMLInputElement }) {
    isFocused = false;
    onblur?.(event);
  }
</script>

<div class="input-wrapper relative">
  {#if label}
    <label
      for={inputId}
      class="absolute left-3 px-1 transition-all duration-200 ease-out pointer-events-none origin-left
        {isFloating ? '-top-2.5 text-xs font-medium bg-gray-800' : 'top-1/2 -translate-y-1/2 text-base'}
        {error ? 'text-red-400' : isFocused ? 'text-brand-accent' : 'text-gray-400'}"
    >
      {label}
    </label>
  {/if}

  <input
    {type}
    id={inputId}
    {name}
    bind:value
    placeholder={isFloating ? placeholder : ''}
    {required}
    {disabled}
    {oninput}
    onblur={handleBlur}
    onfocus={handleFocus}
    class={classes}
    aria-invalid={error ? 'true' : 'false'}
    autocomplete="off"
  />

  {#if error}
    <p class="mt-1 text-xs text-red-400">{error}</p>
  {/if}
</div>

<style>
  .input-wrapper input::placeholder {
    color: var(--color-gray-500);
  }

  /* Focus shimmer effect */
  .input-wrapper::after {
    content: '';
    position: absolute;
    bottom: 0;
    left: 0;
    width: 0;
    height: 2px;
    background: linear-gradient(90deg, transparent, var(--color-brand-accent), transparent);
    transition: width 0.3s ease;
  }

  .input-wrapper:focus-within::after {
    width: 100%;
  }

  /* Respect reduced motion */
  @media (prefers-reduced-motion: reduce) {
    .input-wrapper::after {
      transition: none;
    }

    .input-wrapper label {
      transition: none;
    }
  }
</style>
