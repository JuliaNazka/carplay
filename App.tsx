/**
 * CarPlay Mirror — espelha a tela do iPhone no CarPlay.
 *
 * @format
 */

import { StatusBar } from 'react-native';
import { SafeAreaProvider } from 'react-native-safe-area-context';

import { HomeScreen } from './src/screens/HomeScreen';

function App() {
  return (
    <SafeAreaProvider>
      <StatusBar barStyle="light-content" />
      <HomeScreen />
    </SafeAreaProvider>
  );
}

export default App;
