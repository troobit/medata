/**
 * Navigation store to track page transitions and direction
 */

// Route order for determining slide direction
const ROUTE_ORDER = ['/', '/log', '/history', '/settings'];

function getRouteIndex(path: string): number {
  // Exact match first
  const exactIndex = ROUTE_ORDER.indexOf(path);
  if (exactIndex >= 0) return exactIndex;

  // Check for prefix match (e.g., /log/meal -> /log)
  for (let i = 0; i < ROUTE_ORDER.length; i++) {
    if (ROUTE_ORDER[i] !== '/' && path.startsWith(ROUTE_ORDER[i])) {
      return i;
    }
  }

  return -1;
}

function createNavigationStore() {
  let previousPath = $state('/');
  let currentPath = $state('/');
  let direction = $state<'left' | 'right' | 'none'>('none');

  function navigate(newPath: string) {
    const prevIndex = getRouteIndex(currentPath);
    const newIndex = getRouteIndex(newPath);

    previousPath = currentPath;
    currentPath = newPath;

    if (prevIndex < 0 || newIndex < 0 || prevIndex === newIndex) {
      direction = 'none';
    } else if (newIndex > prevIndex) {
      direction = 'left'; // Content slides left (going forward)
    } else {
      direction = 'right'; // Content slides right (going back)
    }
  }

  return {
    get previousPath() {
      return previousPath;
    },
    get currentPath() {
      return currentPath;
    },
    get direction() {
      return direction;
    },
    navigate
  };
}

export const navigationStore = createNavigationStore();
